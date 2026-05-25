import 'dart:ui';

import 'package:flutter_svg/flutter_svg.dart' show PictureInfo;

/// Parsed, ready-to-render coloring page. Pure data plus dart:ui Paths.
///
/// The [regions] list is **inner-first** — `Painter` (lib/widgets/painter.dart)
/// uses first-region-wins on the stroke's start point, so smaller / overlapping
/// regions must precede the larger ones they sit inside.
///
/// [pictureInfo] is set when the source was an SVG asset and `flutter_svg`
/// could pre-render it. It carries the line-art Picture used as the visual
/// layer (drawn with multiply blend so user fills show through). When null
/// (e.g. JSON manifests, or SVGs that fail to compile), the renderer falls
/// back to drawing [outline] paths.
///
/// [regionFills] runs parallel to [regions] (same length) and holds the
/// original SVG fill color of each region — `null` when unknown (e.g. JSON
/// manifests without a `regionFills` key, or paths whose `fill` attribute
/// didn't parse). Used by the eyedropper as a fallback when pixel sampling
/// is degenerate.
class ColoringPage {
  ColoringPage({
    required this.viewBox,
    required this.regions,
    required this.outline,
    List<Color?>? regionFills,
    this.pictureInfo,
    this.name,
  })  : regionFills =
            regionFills ?? List<Color?>.filled(regions.length, null);

  final Size viewBox;
  final List<Path> regions;
  final List<Color?> regionFills;
  final List<Path> outline;
  final PictureInfo? pictureInfo;
  final String? name;
}

/// Thrown by every public entry point in `lib/coloring/parsing/`.
///
/// [offendingPath] is set whenever the failure can be traced to a specific
/// SVG path-data string — useful for logging which region in a multi-path
/// manifest is broken.
class ColoringParseException implements Exception {
  ColoringParseException(this.message, {this.offendingPath, this.cause});

  final String message;
  final String? offendingPath;
  final Object? cause;

  @override
  String toString() {
    final parts = <String>['ColoringParseException: $message'];
    if (offendingPath != null) parts.add('path: "$offendingPath"');
    if (cause != null) parts.add('cause: $cause');
    return parts.join(' | ');
  }
}
