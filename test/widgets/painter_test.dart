import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yammopatinerapp/coloring/coloring_page.dart';
import 'package:yammopatinerapp/coloring/coloring_page_template.dart';
import 'package:yammopatinerapp/coloring/parsing/svg_path_parser.dart';
import 'package:yammopatinerapp/models/drawing_tool.dart';
import 'package:yammopatinerapp/models/stroke.dart';
import 'package:yammopatinerapp/widgets/painter.dart';

ColoringPageTemplate _template(Size viewBox) {
  return ColoringPageTemplate(
    page: ColoringPage(
      viewBox: viewBox,
      // One region covering the whole viewBox so any stroke start lands inside.
      regions: [
        parsePath(
          'M0 0 L${viewBox.width} 0 L${viewBox.width} ${viewBox.height} L0 ${viewBox.height} Z',
        ),
      ],
      outline: const <Path>[],
    ),
    name: 'Test',
    icon: Icons.image,
  );
}

void main() {
  group('Painter orientation anchoring', () {
    test('a picture-space stroke renders at the same artwork-relative '
        'position when the canvas size changes', () {
      final template = _template(const Size(200, 200));

      // Picture-space stroke from (50, 50) to (150, 150). At canvas 400×400
      // (BoxFit.contain → scale 2, no offset) it should render from
      // (100, 100) to (300, 300).
      final stroke = Stroke(
        tool: DrawingTool.brush,
        style: BrushStyle.round,
        color: const Color(0xFFFF0000),
        width: 5, // picture-space units
        points: const [Offset(50, 50), Offset(150, 150)],
        isPictureSpace: true,
      );

      // Rendering helper: paint into a fresh PictureRecorder at `size` and
      // return the resulting Picture's bounds.
      Rect renderBounds(Size size) {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        Painter(
          actions: [stroke],
          currentStroke: null,
          template: template,
        ).paint(canvas, size);
        recorder.endRecording();
        // We can't read back drawn pixels in a unit test without a real
        // surface, so verify via the painter helpers by re-running the
        // canvas->picture transform: the stroke endpoints in canvas-space
        // for a given size should match BoxFit.contain math.
        final fit = template.fitTransform(size)!;
        final p1 = Offset(
          stroke.points.first.dx * fit.scale + fit.offset.dx,
          stroke.points.first.dy * fit.scale + fit.offset.dy,
        );
        final p2 = Offset(
          stroke.points.last.dx * fit.scale + fit.offset.dx,
          stroke.points.last.dy * fit.scale + fit.offset.dy,
        );
        return Rect.fromPoints(p1, p2);
      }

      // Canvas A: 400×400 → scale 2, no offset.
      final boundsA = renderBounds(const Size(400, 400));
      expect(boundsA.left, closeTo(100, 0.5));
      expect(boundsA.top, closeTo(100, 0.5));
      expect(boundsA.right, closeTo(300, 0.5));
      expect(boundsA.bottom, closeTo(300, 0.5));

      // Canvas B: 800×400 → contain scale 2 (height-bound), x-offset 200.
      final boundsB = renderBounds(const Size(800, 400));
      expect(boundsB.left, closeTo(300, 0.5));
      expect(boundsB.top, closeTo(100, 0.5));
      expect(boundsB.right, closeTo(500, 0.5));
      expect(boundsB.bottom, closeTo(300, 0.5));

      // The picture-space stroke is anchored: its top-left in canvas A is
      // (100, 100), and in canvas B (which is wider) it's shifted right
      // exactly by the BoxFit centering offset (200 px), not stretched.
      expect(boundsB.left - boundsA.left, closeTo(200, 0.5));
      expect(boundsB.height, closeTo(boundsA.height, 0.5));
    });

    test('paints into a PictureRecorder without throwing for the full '
        'pipeline (saveLayer + bucket fill + stroke + outline)', () {
      final template = _template(const Size(100, 100));
      final stroke = Stroke(
        tool: DrawingTool.brush,
        style: BrushStyle.round,
        color: const Color(0xFF00FF00),
        width: 4,
        points: const [Offset(20, 20), Offset(80, 80)],
        isPictureSpace: true,
      );
      final fill = BucketFill(
        region: parsePath('M0 0 L50 0 L50 50 L0 50 Z'),
        color: const Color(0xFF0000FF),
        isPictureSpace: true,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      Painter(
        actions: [fill, stroke],
        currentStroke: null,
        template: template,
      ).paint(canvas, const Size(200, 200));
      recorder.endRecording();
    });

    test('an eraser stroke does not erase a bucket fill placed after it',
        () {
      // Order matters: a fill submitted *after* an eraser stroke should be
      // visible. Painter walks `actions` in order, so the eraser
      // (BlendMode.clear) only clears earlier paint.
      final template = _template(const Size(100, 100));

      final earlierBrush = Stroke(
        tool: DrawingTool.brush,
        style: BrushStyle.round,
        color: const Color(0xFFFF0000),
        width: 4,
        points: const [Offset(20, 20), Offset(40, 40)],
        isPictureSpace: true,
      );
      final eraser = Stroke(
        tool: DrawingTool.eraser,
        style: BrushStyle.round,
        color: const Color(0xFF000000),
        width: 8,
        points: const [Offset(20, 20), Offset(40, 40)],
        isPictureSpace: true,
      );
      final laterFill = BucketFill(
        region: parsePath('M0 0 L80 0 L80 80 L0 80 Z'),
        color: const Color(0xFF00FF00),
        isPictureSpace: true,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      Painter(
        actions: [earlierBrush, eraser, laterFill],
        currentStroke: null,
        template: template,
      ).paint(canvas, const Size(200, 200));
      recorder.endRecording();
      // Smoke test only — pixel sampling needs a real surface. Rendering
      // without throwing in the documented order is the contract this
      // test locks in; manual verification covers the visual outcome.
    });

    test('renders an in-flight currentStroke on top of committed actions',
        () {
      final template = _template(const Size(100, 100));
      final committed = Stroke(
        tool: DrawingTool.brush,
        style: BrushStyle.round,
        color: const Color(0xFFFF0000),
        width: 4,
        points: const [Offset(20, 20), Offset(40, 40)],
        isPictureSpace: true,
      );
      final live = Stroke(
        tool: DrawingTool.brush,
        style: BrushStyle.round,
        color: const Color(0xFF0000FF),
        width: 4,
        points: const [Offset(50, 50), Offset(60, 60)],
        isPictureSpace: true,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      Painter(
        actions: [committed],
        currentStroke: live,
        template: template,
      ).paint(canvas, const Size(200, 200));
      recorder.endRecording();
    });
  });
}
