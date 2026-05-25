import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yammopatinerapp/coloring/coloring_page.dart';
import 'package:yammopatinerapp/coloring/parsing/coloring_page_loader.dart';
import 'package:yammopatinerapp/coloring/parsing/svg_importer.dart';

void main() {
  group('importRawSvg', () {
    test('classifies via <g id="regions"> / <g id="outline">', () async {
      final source = File('test/fixtures/sample.svg').readAsStringSync();
      final manifest = await importRawSvg(source);

      expect(manifest.viewBox, const Size(100, 100));
      expect(manifest.regions, hasLength(2));
      expect(manifest.outline, hasLength(1));
      expect(manifest.name, 'Sample');
    });

    test('classifies fill="none"+stroke as outline, light fill as region', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path d="M0 0 L10 10" stroke="black" fill="none"/>
  <path d="M0 0 L10 0 L10 10 Z" fill="yellow"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.outline, hasLength(1));
      expect(manifest.regions, hasLength(1));
    });

    test('classifies dark fills as outline (line art)', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path d="M0 0 L10 0 L10 10 Z" fill="#000"/>
  <path d="M20 20 L30 20 L30 30 Z" fill="black"/>
  <path d="M40 40 L50 40 L50 50 Z" fill="#7E7E7D"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.outline, hasLength(3));
      expect(manifest.regions, isEmpty);
    });

    test('classifies light fills as regions (colorable areas)', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path d="M0 0 L10 0 L10 10 Z" fill="#FEFEFE"/>
  <path d="M20 20 L30 20 L30 30 Z" fill="white"/>
  <path d="M40 40 L50 40 L50 50 Z" fill="#aaffaa"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.regions, hasLength(3));
      expect(manifest.outline, isEmpty);
    });

    test('class="outline" forces outline classification', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path d="M0 0 L1 1" class="outline" fill="red"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.outline, hasLength(1));
      expect(manifest.regions, isEmpty);
    });

    test('group id beats fill/stroke heuristic', () async {
      // Path has fill="none" stroke="black" — heuristic alone would call it
      // outline — but the <g id="regions"> ancestor wins.
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g id="regions">
    <path d="M0 0 L1 1" fill="none" stroke="black"/>
  </g>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.regions, hasLength(1));
      expect(manifest.outline, isEmpty);
    });

    test('skips <path> elements with empty d=', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <g id="regions">
    <path d=""/>
    <path/>
    <path d="M0 0 L1 1"/>
  </g>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.regions, hasLength(1));
    });

    test('throws on missing <svg>', () async {
      expect(
        () => importRawSvg('<root/>'),
        throwsA(isA<ColoringParseException>()),
      );
    });

    test('throws when there is no viewBox AND no width/height fallback', () async {
      expect(
        () => importRawSvg(
          '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
        ),
        throwsA(isA<ColoringParseException>()),
      );
    });

    test('falls back to width/height when viewBox is missing', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600">
  <path d="M0 0 L10 10"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.viewBox, const Size(800, 600));
      expect(manifest.regions, hasLength(1));
    });

    test('strips px suffix on width/height fallback', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="800px" height="600px">
  <path d="M0 0 L10 10"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.viewBox, const Size(800, 600));
    });

    test('throws on malformed viewBox', () async {
      expect(
        () => importRawSvg(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 nope nope"/>',
        ),
        throwsA(isA<ColoringParseException>()),
      );
    });

    test('throws on non-translate transform on a group ancestor', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g transform="scale(2)">
    <path d="M0 0 L10 10"/>
  </g>
</svg>
''';
      expect(
        () => importRawSvg(svg),
        throwsA(isA<ColoringParseException>()),
      );
    });

    test('applies translate transform on the path', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path d="M0 0 L10 10" transform="translate(5,5)"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.regions, hasLength(1));
      // Round-trip via parsePath to verify the shift landed in the data.
      final page = await loadFromManifest(manifest);
      expect(page.regions.first.getBounds(), const Rect.fromLTRB(5, 5, 15, 15));
    });

    test('accumulates translates from ancestor + path', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g transform="translate(10, 20)">
    <path d="M0 0 L10 10" transform="translate(5, 5)"/>
  </g>
</svg>
''';
      final manifest = await importRawSvg(svg);
      final page = await loadFromManifest(manifest);
      expect(page.regions.first.getBounds(), const Rect.fromLTRB(15, 25, 25, 35));
    });

    test('explicit <g id="regions"> with no outline group keeps outline empty', () async {
      // Author intent: regions only, no line art. The importer must not
      // synthesize an outline from regions in this case.
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g id="regions">
    <path d="M0 0 L10 10 L10 0 Z"/>
  </g>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.regions, hasLength(1));
      expect(manifest.outline, isEmpty);
    });

    test('mixed dark + light fills split into outline + regions naturally', () async {
      // The realistic potrace --color case: line-art paths come out dark,
      // colorable interiors come out light. They land in the right buckets
      // without any explicit grouping or mirror fallback.
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
  <path d="M0 0 L10 0 L10 10 Z" fill="#7E7E7D"/>
  <path d="M20 20 L30 20 L30 30 Z" fill="#FEFEFE"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.outline, hasLength(1));
      expect(manifest.regions, hasLength(1));
    });

    test('leaves relative coordinates alone under translate', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <path d="M10 10 l5 5" transform="translate(100, 200)"/>
</svg>
''';
      final manifest = await importRawSvg(svg);
      final page = await loadFromManifest(manifest);
      // M absolute → shifts to (110, 210). The relative l 5 5 stays as a
      // delta, so endpoint is (115, 215).
      expect(
        page.regions.first.getBounds(),
        const Rect.fromLTRB(110, 210, 115, 215),
      );
    });

    test('throws on malformed XML', () async {
      expect(
        () => importRawSvg('<svg viewBox="0 0 1 1"><path d="M0 0"/'),
        throwsA(isA<ColoringParseException>()),
      );
    });
  });

  group('end-to-end: importRawSvg → loadFromManifest', () {
    test('a multi-region SVG produces non-trivial Path bounds', () async {
      const svg = '''
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600" data-name="Multi">
  <g id="regions">
    <path d="M 100 100 L 300 100 L 300 250 L 100 250 Z"/>
    <path d="M 400 150 C 420 150 440 170 440 190 C 440 210 420 230 400 230 C 380 230 360 210 360 190 C 360 170 380 150 400 150 Z"/>
    <path d="M 500 400 L 700 400 L 700 500 L 500 500 Z"/>
  </g>
  <g id="outline">
    <path d="M 50 50 L 750 50 L 750 550 L 50 550 Z"/>
  </g>
</svg>
''';
      final manifest = await importRawSvg(svg);
      expect(manifest.viewBox, const Size(800, 600));
      expect(manifest.regions, hasLength(3));
      expect(manifest.outline, hasLength(1));
      expect(manifest.name, 'Multi');

      final page = await loadFromManifest(manifest);
      expect(page.regions, hasLength(3));
      expect(page.outline, hasLength(1));
      for (final region in page.regions) {
        expect(region.getBounds().shortestSide, greaterThan(0));
      }
    });
  });
}
