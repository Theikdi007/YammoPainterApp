import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' show PictureInfo;

import '../models/drawing_template.dart';
import 'coloring_page.dart';

/// Adapts a [ColoringPage] (data-only) to the runtime [DrawingTemplate]
/// interface that `Painter` and the picker know how to consume.
///
/// One instance per coloring page. Caches the BoxFit.contain transform of
/// the page's region and outline paths keyed by canvas [Size] — the painter
/// rebuilds on every pan event, and re-transforming hundreds of paths each
/// frame would be wasteful.
class ColoringPageTemplate extends DrawingTemplate {
  ColoringPageTemplate({
    required this.page,
    required String name,
    required IconData icon,
  })  : _name = name,
        _icon = icon;

  final ColoringPage page;
  final String _name;
  final IconData _icon;

  final Map<Size, _Fitted> _cache = <Size, _Fitted>{};

  @override
  String get name => _name;

  @override
  IconData get icon => _icon;

  /// All asset SVGs share the same viewBox (3508×2480), so picture-space
  /// stroke storage gives us a stable coordinate system that survives canvas
  /// resizes (orientation changes) and is consistent across templates.
  @override
  Size? get naturalSize =>
      page.viewBox.isEmpty ? null : page.viewBox;

  @override
  List<Path> buildRegions(Size size) => _fit(size).regions;

  @override
  Path buildFillPath(Size size) {
    // The Painter uses this only as a fallback clip when no region contains
    // the stroke's first point. For asset-backed pages we approximate with
    // the BoxFit.contain rect of the viewBox: chaining Path.combine across
    // hundreds of region paths is both slow (called per paint) and prone to
    // Skia "Path.combine() failed / NaN" failures on degenerate inputs from
    // raw vectorizer output.
    if (size.isEmpty || page.viewBox.isEmpty || page.regions.isEmpty) {
      return Path();
    }
    final scale = math.min(
      size.width / page.viewBox.width,
      size.height / page.viewBox.height,
    );
    final w = page.viewBox.width * scale;
    final h = page.viewBox.height * scale;
    final dx = (size.width - w) / 2;
    final dy = (size.height - h) / 2;
    return Path()..addRect(Rect.fromLTWH(dx, dy, w, h));
  }

  @override
  void paintOutline(Canvas canvas, Size size) {
    final pictureInfo = page.pictureInfo;
    if (pictureInfo != null) {
      _paintPicture(canvas, size, pictureInfo, blendMultiply: true);
      return;
    }
    // Fallback for non-SVG sources or when flutter_svg failed to render the
    // file: draw the parsed outline paths as thin strokes.
    for (final path in _fit(size).outline) {
      canvas.drawPath(path, _outlinePaint);
    }
  }

  /// Picker thumbnails have no user strokes underneath, so we skip the
  /// `saveLayer` + multiply blend used by [paintOutline]. Plain [drawPicture]
  /// is much cheaper to repaint per frame, which is what the bottom-sheet
  /// grid does on every layout/scroll tick.
  @override
  void paintPreview(Canvas canvas, Size size) {
    final pictureInfo = page.pictureInfo;
    if (pictureInfo != null) {
      _paintPicture(canvas, size, pictureInfo, blendMultiply: false);
      return;
    }
    for (final path in _fit(size).outline) {
      canvas.drawPath(path, _outlinePaint);
    }
  }

  /// Faint tracing underlay for PaintMode.draw. Renders the same line art as
  /// [paintPreview] but inside an alpha layer so the whole picture drops to
  /// ~25% opacity — enough to trace over, light enough that user strokes
  /// clearly sit on top.
  @override
  void paintGuide(Canvas canvas, Size size) {
    final pictureInfo = page.pictureInfo;
    if (pictureInfo != null) {
      final svgSize = pictureInfo.size;
      if (svgSize.isEmpty || size.isEmpty) return;
      final scale = math.min(
        size.width / svgSize.width,
        size.height / svgSize.height,
      );
      final rect = Rect.fromLTWH(
        (size.width - svgSize.width * scale) / 2,
        (size.height - svgSize.height * scale) / 2,
        svgSize.width * scale,
        svgSize.height * scale,
      );
      // Layer paint alpha modulates everything drawn in the layer on restore.
      canvas.saveLayer(rect, Paint()..color = const Color(0x40FFFFFF));
      _paintPicture(canvas, size, pictureInfo, blendMultiply: false);
      canvas.restore();
      return;
    }
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x40202020)
      ..isAntiAlias = true;
    for (final path in _fit(size).outline) {
      canvas.drawPath(path, guidePaint);
    }
  }

  void _paintPicture(
    Canvas canvas,
    Size size,
    PictureInfo info, {
    required bool blendMultiply,
  }) {
    final svgSize = info.size;
    if (svgSize.isEmpty || size.isEmpty) return;

    final scale = math.min(
      size.width / svgSize.width,
      size.height / svgSize.height,
    );
    final dx = (size.width - svgSize.width * scale) / 2;
    final dy = (size.height - svgSize.height * scale) / 2;

    if (blendMultiply) {
      // Lets user-stroke colors show through the SVG's white background
      // while the dark line art stays dark on top. saveLayer is required
      // because the blend must compose against the underlying canvas, not
      // an undefined offscreen surface.
      final layerRect = Rect.fromLTWH(
        dx,
        dy,
        svgSize.width * scale,
        svgSize.height * scale,
      );
      canvas.saveLayer(layerRect, Paint()..blendMode = BlendMode.multiply);
      canvas.translate(dx, dy);
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      canvas.restore();
    } else {
      canvas.save();
      canvas.translate(dx, dy);
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      canvas.restore();
    }
  }

  _Fitted _fit(Size size) {
    if (size.isEmpty || page.viewBox.isEmpty) {
      return const _Fitted(<Path>[], <Path>[]);
    }
    final cached = _cache[size];
    if (cached != null) return cached;

    final matrix = _fitContain(page.viewBox, size).storage;
    final regions = page.regions
        .map((p) => p.transform(matrix))
        .toList(growable: false);
    final outline = page.outline
        .map((p) => p.transform(matrix))
        .toList(growable: false);
    final fitted = _Fitted(regions, outline);
    _cache[size] = fitted;
    return fitted;
  }

  static Matrix4 _fitContain(Size from, Size to) {
    final scale = math.min(to.width / from.width, to.height / from.height);
    final dx = (to.width - from.width * scale) / 2;
    final dy = (to.height - from.height * scale) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }
}

class _Fitted {
  const _Fitted(this.regions, this.outline);
  final List<Path> regions;
  final List<Path> outline;
}

// Stroke (not fill) so chunky dark shapes from a vectorizer (a frame backing,
// a filled barn body, etc.) render as thin perimeter outlines instead of
// solid filled rectangles. Width 1.0 keeps line-art shapes from looking
// double-hairlined while staying lighter than the previous 2.0.
final Paint _outlinePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.0
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round
  ..color = const Color(0xFF202020)
  ..isAntiAlias = true;
