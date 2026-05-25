import 'dart:ui';

import 'coloring_page.dart';

/// Serializable description of a coloring page. Holds raw SVG path-data
/// strings; turn into a [ColoringPage] (with dart:ui Paths) via
/// `loadFromManifest` in `parsing/coloring_page_loader.dart`.
///
/// JSON shape:
/// ```json
/// {
///   "name": "Optional",
///   "viewBox": {"width": 800, "height": 600},
///   "regions": ["M..", "M..", ...],
///   "outline": ["M..", ...]
/// }
/// ```
class ColoringPageManifest {
  ColoringPageManifest({
    required this.viewBox,
    required this.regions,
    required this.outline,
    List<String?>? regionFills,
    this.name,
  }) : regionFills =
            regionFills ?? List<String?>.filled(regions.length, null);

  final Size viewBox;
  final List<String> regions;

  /// Original SVG fill color per region, parallel to [regions]. `null` when
  /// the source path had no parseable `fill`. Used by the eyedropper as a
  /// fallback when canvas pixel sampling is degenerate.
  final List<String?> regionFills;
  final List<String> outline;
  final String? name;

  factory ColoringPageManifest.fromJson(Map<String, dynamic> json) {
    final viewBoxRaw = json['viewBox'];
    if (viewBoxRaw is! Map) {
      throw ColoringParseException(
        'manifest "viewBox" must be a {width, height} object',
      );
    }
    final width = (viewBoxRaw['width'] as num?)?.toDouble();
    final height = (viewBoxRaw['height'] as num?)?.toDouble();
    if (width == null || height == null) {
      throw ColoringParseException(
        'manifest "viewBox" is missing numeric width/height',
      );
    }

    final regionsRaw = json['regions'];
    if (regionsRaw is! List) {
      throw ColoringParseException(
        'manifest "regions" must be an array of path-data strings',
      );
    }
    final outlineRaw = json['outline'];
    if (outlineRaw != null && outlineRaw is! List) {
      throw ColoringParseException(
        'manifest "outline", when present, must be an array',
      );
    }

    final regionFillsRaw = json['regionFills'];
    if (regionFillsRaw != null && regionFillsRaw is! List) {
      throw ColoringParseException(
        'manifest "regionFills", when present, must be an array',
      );
    }

    return ColoringPageManifest(
      viewBox: Size(width, height),
      regions: List<String>.from(regionsRaw),
      regionFills: regionFillsRaw == null
          ? null
          : List<String?>.from(
              (regionFillsRaw).map((e) => e as String?),
            ),
      outline: outlineRaw == null ? const <String>[] : List<String>.from(outlineRaw),
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (name != null) 'name': name,
        'viewBox': <String, double>{
          'width': viewBox.width,
          'height': viewBox.height,
        },
        'regions': regions,
        if (regionFills.any((c) => c != null)) 'regionFills': regionFills,
        'outline': outline,
      };
}
