import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yammopatinerapp/coloring/coloring_page.dart';
import 'package:yammopatinerapp/coloring/coloring_page_manifest.dart';
import 'package:yammopatinerapp/coloring/parsing/coloring_page_loader.dart';

void main() {
  group('loadFromManifest', () {
    test('parses regions and outline into Path objects', () async {
      final manifest = ColoringPageManifest(
        viewBox: const Size(100, 100),
        regions: const ['M10 10 L30 10 L30 30 L10 30 Z'],
        outline: const ['M0 0 L100 0 L100 100 L0 100 Z'],
        name: 'Test',
      );
      final page = await loadFromManifest(manifest);
      expect(page.viewBox, const Size(100, 100));
      expect(page.regions, hasLength(1));
      expect(page.outline, hasLength(1));
      expect(
        page.regions.first.getBounds(),
        const Rect.fromLTRB(10, 10, 30, 30),
      );
      expect(page.name, 'Test');
    });

    test('propagates ColoringParseException for malformed region', () async {
      final manifest = ColoringPageManifest(
        viewBox: const Size(100, 100),
        regions: const ['definitely not svg'],
        outline: const <String>[],
      );
      expect(
        () => loadFromManifest(manifest),
        throwsA(isA<ColoringParseException>()),
      );
    });
  });

  group('ColoringPageManifest JSON codec', () {
    test('decodes the sample fixture and round-trips', () {
      final source = File('test/fixtures/sample_manifest.json').readAsStringSync();
      final manifest = ColoringPageManifest.fromJson(
        json.decode(source) as Map<String, dynamic>,
      );

      expect(manifest.viewBox, const Size(100, 100));
      expect(manifest.regions, hasLength(2));
      expect(manifest.outline, hasLength(1));
      expect(manifest.name, 'Sample');

      final reEncoded = json.encode(manifest.toJson());
      final reParsed = ColoringPageManifest.fromJson(
        json.decode(reEncoded) as Map<String, dynamic>,
      );
      expect(reParsed.regions, equals(manifest.regions));
      expect(reParsed.outline, equals(manifest.outline));
      expect(reParsed.name, manifest.name);
      expect(reParsed.viewBox, manifest.viewBox);
    });

    test('throws when viewBox is missing', () {
      expect(
        () => ColoringPageManifest.fromJson(<String, dynamic>{
          'regions': <String>[],
        }),
        throwsA(isA<ColoringParseException>()),
      );
    });

    test('throws when regions is not an array', () {
      expect(
        () => ColoringPageManifest.fromJson(<String, dynamic>{
          'viewBox': {'width': 10, 'height': 10},
          'regions': 'M0 0 L1 1',
        }),
        throwsA(isA<ColoringParseException>()),
      );
    });

    test('treats outline as optional (defaults to empty)', () {
      final manifest = ColoringPageManifest.fromJson(<String, dynamic>{
        'viewBox': {'width': 10, 'height': 10},
        'regions': <String>['M0 0 L1 1'],
      });
      expect(manifest.outline, isEmpty);
    });
  });

  group('loadFromUrl', () {
    test('loads a JSON manifest by Content-Type', () async {
      final manifestJson = json.encode(<String, dynamic>{
        'viewBox': {'width': 50, 'height': 50},
        'regions': ['M0 0 L10 10'],
        'outline': <String>[],
      });
      final client = MockClient((req) async {
        return http.Response(
          manifestJson,
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final page = await loadFromUrl(
        'https://example.test/x',
        client: client,
      );
      expect(page.regions, hasLength(1));
      expect(page.viewBox, const Size(50, 50));
    });

    test('loads SVG content by Content-Type', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 50 50">
  <g id="regions"><path d="M0 0 L10 10"/></g>
</svg>
''';
      final client = MockClient((req) async {
        return http.Response(
          svg,
          200,
          headers: {'content-type': 'image/svg+xml'},
        );
      });
      final page = await loadFromUrl(
        'https://example.test/x',
        client: client,
      );
      expect(page.regions, hasLength(1));
    });

    test('throws ColoringParseException on 404', () async {
      final client = MockClient((req) async => http.Response('', 404));
      expect(
        () => loadFromUrl('https://example.test/x', client: client),
        throwsA(isA<ColoringParseException>()),
      );
    });

    test('falls back to URL extension when Content-Type is unhelpful', () async {
      final manifestJson = json.encode(<String, dynamic>{
        'viewBox': {'width': 1, 'height': 1},
        'regions': ['M0 0 L1 1'],
      });
      final client = MockClient((req) async {
        return http.Response(
          manifestJson,
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      });
      final page = await loadFromUrl(
        'https://example.test/page.json',
        client: client,
      );
      expect(page.regions, hasLength(1));
    });
  });
}
