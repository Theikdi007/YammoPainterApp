import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yammopatinerapp/coloring/coloring_page.dart';
import 'package:yammopatinerapp/coloring/coloring_page_template.dart';
import 'package:yammopatinerapp/coloring/parsing/svg_path_parser.dart';

ColoringPage _pageWithRect({required Size viewBox}) {
  return ColoringPage(
    viewBox: viewBox,
    regions: [parsePath('M0 0 L50 0 L50 50 L0 50 Z')],
    outline: [parsePath('M0 0 L50 0 L50 50 L0 50 Z')],
    name: 'Test',
  );
}

ColoringPageTemplate _template(ColoringPage page) {
  return ColoringPageTemplate(
    page: page,
    name: 'Test',
    icon: Icons.star,
  );
}

void main() {
  group('ColoringPageTemplate', () {
    test('fits regions into a same-aspect canvas (uniform scale)', () {
      final t = _template(_pageWithRect(viewBox: const Size(200, 200)));
      // viewBox 200×200 in 400×400 canvas → scale 2x, no letterbox.
      // Region at (0,0,50,50) → (0,0,100,100).
      final regions = t.buildRegions(const Size(400, 400));
      expect(regions, hasLength(1));
      final b = regions.first.getBounds();
      expect(b.left, closeTo(0, 0.5));
      expect(b.top, closeTo(0, 0.5));
      expect(b.right, closeTo(100, 0.5));
      expect(b.bottom, closeTo(100, 0.5));
    });

    test('letterboxes when aspects differ (BoxFit.contain)', () {
      final t = _template(_pageWithRect(viewBox: const Size(200, 200)));
      // Canvas 400×200: contain scale = min(2, 1) = 1; centered horizontally,
      // so a (0,0,50,50) region lands at (100,0,150,50).
      final regions = t.buildRegions(const Size(400, 200));
      final b = regions.first.getBounds();
      expect(b.left, closeTo(100, 0.5));
      expect(b.top, closeTo(0, 0.5));
      expect(b.right, closeTo(150, 0.5));
      expect(b.bottom, closeTo(50, 0.5));
    });

    test('caches the transformed list per Size', () {
      final t = _template(_pageWithRect(viewBox: const Size(100, 100)));
      final a = t.buildRegions(const Size(200, 200));
      final b = t.buildRegions(const Size(200, 200));
      expect(identical(a, b), isTrue);
    });

    test('returns empty regions for a zero-sized canvas', () {
      final t = _template(_pageWithRect(viewBox: const Size(100, 100)));
      expect(t.buildRegions(Size.zero), isEmpty);
      expect(t.buildFillPath(Size.zero).getBounds(), Rect.zero);
    });

    test('paintOutline draws to a recording canvas without throwing', () {
      final t = _template(_pageWithRect(viewBox: const Size(100, 100)));
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      t.paintOutline(canvas, const Size(200, 200));
      recorder.endRecording();
    });

    test('buildFillPath returns a non-empty union when regions exist', () {
      final t = _template(_pageWithRect(viewBox: const Size(100, 100)));
      final fill = t.buildFillPath(const Size(200, 200));
      expect(fill.getBounds().shortestSide, greaterThan(0));
    });

    test('exposes the configured name and icon', () {
      final t = ColoringPageTemplate(
        page: _pageWithRect(viewBox: const Size(100, 100)),
        name: 'Farm Friends',
        icon: Icons.agriculture_outlined,
      );
      expect(t.name, 'Farm Friends');
      expect(t.icon, Icons.agriculture_outlined);
    });
  });
}
