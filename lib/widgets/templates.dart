import 'package:flutter/material.dart';

import '../coloring/coloring_page_template.dart';
import '../coloring/parsing/coloring_page_loader.dart';
import '../models/drawing_template.dart';

/// Templates the picker shows. All entries are asset-backed and appended by
/// [initTemplates], which **must** be awaited from `main()` before `runApp`
/// so the list is stable by first render.
final List<DrawingTemplate> kTemplates = <DrawingTemplate>[];

bool _initialized = false;

/// Asset SVG filenames under `assets/templates/`. Order here is the order the
/// picker shows them.
const List<String> _assetFilenames = <String>[
  'COLORING-PAGE-01.svg',
  'COLORING-PAGE-03.svg',
  'COLORING-PAGE-04.svg',
  'COLORING-PAGE-05.svg',
  'COLORING-PAGE-06.svg',
  'COLORING-PAGE-07.svg',
  'COLORING-PAGE-08.svg',
  'COLORING-PAGE-09.svg',
  'COLORING-PAGE-10.svg',
  'COLORING-PAGE-11.svg',
  'COLORING-PAGE-12.svg',
  'COLORING-PAGE-13.svg',
  'COLORING-PAGE-14.svg',
];

/// Loads every asset-backed coloring page and appends a
/// [ColoringPageTemplate] for each. Idempotent. A failed load is logged
/// (visible via `flutter run` console / `flutter logs`) and that template is
/// skipped — the picker still works with whatever loaded successfully.
Future<void> initTemplates() async {
  if (_initialized) return;
  _initialized = true;

  for (final filename in _assetFilenames) {
    await _tryLoad(
      assetPath: 'assets/templates/$filename',
      name: _displayNameFor(filename),
      icon: Icons.image_outlined,
    );
  }
}

/// Turns `COLORING-PAGE-07.svg` into `Page 07`.
String _displayNameFor(String filename) {
  final match = RegExp(r'(\d+)').firstMatch(filename);
  return match != null ? 'Page ${match.group(1)}' : filename;
}

Future<void> _tryLoad({
  required String assetPath,
  required String name,
  required IconData icon,
}) async {
  try {
    final page = await loadFromAssetBundle(assetPath);
    kTemplates.add(
      ColoringPageTemplate(page: page, name: name, icon: icon),
    );
  } catch (e, stack) {
    debugPrint('initTemplates: failed to load "$assetPath" ($name): $e');
    debugPrintStack(stackTrace: stack);
  }
}
