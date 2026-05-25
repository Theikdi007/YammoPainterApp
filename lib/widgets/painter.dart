import 'package:flutter/material.dart';

import '../models/drawing_template.dart';
import '../models/drawing_tool.dart';
import '../models/stroke.dart';

/// Renders the drawing.
///
/// Pass order, top to bottom:
/// 1. `saveLayer` — actions compose into a private layer so eraser
///    `BlendMode.clear` only erases user paint, not the canvas's white
///    background underneath.
/// 2. **[actions]** — strokes (brush/eraser) and bucket fills, drawn in
///    submission order so an eraser only erases what came *before* it. A
///    fill placed after an eraser stroke stays visible.
/// 3. **[currentStroke]** — the in-flight pan stroke, drawn after all
///    committed actions so the user sees their brush as they move it.
/// 4. Layer restored.
/// 5. **SVG outline** drawn on top of the layer (via `paintOutline`,
///    multiply-blended in `ColoringPageTemplate`) — the line art always
///    wins visually.
class Painter extends CustomPainter {
  Painter({
    required this.actions,
    required this.currentStroke,
    this.template,
  });

  final List<DrawAction> actions;
  final Stroke? currentStroke;
  final DrawingTemplate? template;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = template?.fitTransform(size);
    final scale = fit?.scale ?? 1.0;
    final offset = fit?.offset ?? Offset.zero;

    final regions = template?.buildRegions(size) ?? const <Path>[];

    // Actions go into one isolated layer so BlendMode.clear used by the
    // eraser only affects user paint within this layer. Without it,
    // BlendMode.clear would punch through to whatever is below — for the
    // exported PNG that's transparent, which is wrong.
    final layerRect = Offset.zero & size;
    canvas.saveLayer(layerRect, Paint());

    for (final action in actions) {
      if (action is BucketFill) {
        final region = action.isPictureSpace
            ? _transformPath(action.region, scale, offset)
            : action.region;
        canvas.drawPath(region, Paint()..color = action.color);
      } else if (action is Stroke) {
        _paintStroke(canvas, action, regions, scale, offset);
      }
    }

    final live = currentStroke;
    if (live != null) {
      _paintStroke(canvas, live, regions, scale, offset);
    }

    canvas.restore();

    // SVG outline on top (kept outside the layer so erasing user paint
    // never wipes the line art).
    template?.paintOutline(canvas, size);
  }

  void _paintStroke(
    Canvas canvas,
    Stroke stroke,
    List<Path> regions,
    double scale,
    Offset offset,
  ) {
    if (stroke.points.isEmpty) return;

    final canvasPoints = stroke.isPictureSpace
        ? stroke.points
            .map((p) => Offset(
                  p.dx * scale + offset.dx,
                  p.dy * scale + offset.dy,
                ))
            .toList(growable: false)
        : stroke.points;

    final canvasWidth = stroke.isPictureSpace ? stroke.width * scale : stroke.width;
    final paint = _paintFor(
      stroke.style,
      stroke.color,
      canvasWidth,
      isEraser: stroke.tool == DrawingTool.eraser,
    );

    // Brush strokes (not eraser) are clipped to the region containing their
    // first point, so colors stay inside the shape boundaries the artwork
    // implies. Eraser is unclipped — the user expects to erase across
    // boundaries. If no region matches the start, drop the stroke (keeps
    // free-flow paint from escaping the picture frame).
    Path? clipPath;
    if (stroke.tool != DrawingTool.eraser && regions.isNotEmpty) {
      double? bestArea;
      for (final region in regions) {
        if (!region.contains(canvasPoints.first)) continue;
        final b = region.getBounds();
        final area = b.width * b.height;
        if (bestArea == null || area < bestArea) {
          bestArea = area;
          clipPath = region;
        }
      }
      if (clipPath == null) return;
    }

    canvas.save();
    if (clipPath != null) canvas.clipPath(clipPath);

    if (canvasPoints.length == 1) {
      canvas.drawCircle(canvasPoints.first, canvasWidth / 2, paint);
    } else {
      _drawTaperedSmoothPath(canvas, canvasPoints, paint, canvasWidth);
    }

    canvas.restore();
  }

  /// Walks [points] and emits a single Path with cubic curves through every
  /// sample (Catmull-Rom-to-Bezier). The first and last ~3 segments are
  /// drawn separately at progressively narrower widths to give a mild
  /// hand-drawn taper.
  void _drawTaperedSmoothPath(
    Canvas canvas,
    List<Offset> points,
    Paint basePaint,
    double width,
  ) {
    if (points.length == 2) {
      canvas.drawLine(points[0], points[1], basePaint);
      return;
    }

    // 0 = full width, 1 = full width; segments inside taperHead/Tail get
    // scaled down to this fraction of the width.
    const taperHead = 3;
    const taperTail = 3;
    const minTaperFactor = 0.6;

    final n = points.length;
    for (var i = 0; i < n - 1; i++) {
      double factor = 1.0;
      if (i < taperHead) {
        factor = minTaperFactor +
            (1.0 - minTaperFactor) * ((i + 1) / (taperHead + 1));
      } else if (i >= n - 1 - taperTail) {
        final remaining = n - 1 - i; // 1..taperTail
        factor = minTaperFactor +
            (1.0 - minTaperFactor) * (remaining / (taperTail + 1));
      }

      final segmentPaint = Paint()
        ..color = basePaint.color
        ..strokeWidth = width * factor
        ..strokeCap = basePaint.strokeCap
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = basePaint.isAntiAlias
        ..maskFilter = basePaint.maskFilter
        ..blendMode = basePaint.blendMode;

      canvas.drawPath(_segmentSmoothPath(points, i), segmentPaint);
    }
  }

  /// One smoothed sub-path covering segment index `i` (from `points[i]` to
  /// `points[i+1]`), with control points borrowed from neighbors so the
  /// curve stays C1-continuous with adjacent segments.
  Path _segmentSmoothPath(List<Offset> points, int i) {
    final p0 = i > 0 ? points[i - 1] : points[i];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = i + 2 < points.length ? points[i + 2] : p2;

    final c1 = Offset(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
    );
    final c2 = Offset(
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
    );

    return Path()
      ..moveTo(p1.dx, p1.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }

  /// Paint configuration for a brush style. Width is in canvas-space.
  Paint _paintFor(
    BrushStyle style,
    Color color,
    double width, {
    required bool isEraser,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true;

    if (isEraser) {
      paint
        ..color = const Color(0xFF000000)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.clear;
      return paint;
    }

    paint.color = color;
    switch (style) {
      case BrushStyle.round:
        paint
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
      case BrushStyle.soft:
        paint
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.3);
      case BrushStyle.marker:
        paint
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.miter
          ..color = color.withValues(alpha: 0.55);
      case BrushStyle.pencil:
        paint
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width * 0.6
          ..color = color.withValues(alpha: 0.7);
    }
    return paint;
  }

  Path _transformPath(Path src, double scale, Offset offset) {
    final m = Matrix4.identity()
      ..translateByDouble(offset.dx, offset.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    return src.transform(m.storage);
  }

  @override
  bool shouldRepaint(covariant Painter oldDelegate) =>
      oldDelegate.actions != actions ||
      oldDelegate.currentStroke != currentStroke ||
      oldDelegate.template != template;
}
