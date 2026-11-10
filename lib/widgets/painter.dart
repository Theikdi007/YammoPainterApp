import 'dart:ui' as ui;

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
///
/// [paintMode] selects between the two template behaviors:
/// - `color` (default): strokes clip to the picture's regions and the line
///   art is drawn dark on top — the coloring-book experience.
/// - `draw`: strokes aren't clipped and, when a template is set, the artwork
///   renders faintly *underneath* the strokes as a tracing guide.
class Painter extends CustomPainter {
  Painter({
    required this.actions,
    required this.currentStroke,
    this.template,
    this.paintMode = PaintMode.color,
    this.backgroundImage,
    this.selectionRect,
  });

  final List<DrawAction> actions;
  final Stroke? currentStroke;
  final DrawingTemplate? template;
  final PaintMode paintMode;

  /// A raster image painted as the bottom of the editable stroke layer — used to
  /// "repaint" a previously saved drawing: the user draws on top of it, can
  /// erase into it, and the export includes it. Null in normal free-draw /
  /// coloring sessions.
  final ui.Image? backgroundImage;

  /// Canvas-space bounds of the currently selected element — drawn as a
  /// highlight box. Null when nothing is selected. Not part of the exported PNG
  /// (the controller clears the selection before rendering for save).
  final Rect? selectionRect;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = template?.fitTransform(size);
    final scale = fit?.scale ?? 1.0;
    final offset = fit?.offset ?? Offset.zero;

    // Regions are needed to clip any coloring stroke (those carry
    // `clipToRegions`); compute them whenever a picture is active. Whether a
    // given stroke actually clips is decided per-stroke in `_paintStroke`.
    final regions = template?.buildRegions(size) ?? const <Path>[];

    // Draw mode: faint tracing guide goes *under* the stroke layer so freehand
    // strokes sit clearly on top of the line art.
    if (paintMode == PaintMode.draw) {
      template?.paintGuide(canvas, size);
    }

    // Actions go into one isolated layer so BlendMode.clear used by the
    // eraser only affects user paint within this layer. Without it,
    // BlendMode.clear would punch through to whatever is below — for the
    // exported PNG that's transparent, which is wrong.
    final layerRect = Offset.zero & size;
    canvas.saveLayer(layerRect, Paint());

    // Repaint backdrop: the saved artwork, fitted (contain) and centred. Drawn
    // *inside* the stroke layer and before the actions so it's editable — the
    // eraser (BlendMode.clear) can rub it out (revealing the white canvas) and
    // undo restores it, just like any painted content. Erasing past its edges
    // still only clears within this layer, never punching the canvas to nothing.
    final bg = backgroundImage;
    if (bg != null) {
      final srcW = bg.width.toDouble();
      final srcH = bg.height.toDouble();
      final bgScale =
          (size.width / srcW).clamp(0.0, size.height / srcH).toDouble();
      final w = srcW * bgScale;
      final h = srcH * bgScale;
      final dst = Rect.fromLTWH(
        (size.width - w) / 2,
        (size.height - h) / 2,
        w,
        h,
      );
      canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, srcW, srcH),
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    for (final action in actions) {
      if (action is BucketFill) {
        final region = action.isPictureSpace
            ? _transformPath(action.region, scale, offset)
            : action.region;
        canvas.drawPath(region, Paint()..color = action.color);
      } else if (action is RasterFill) {
        // Drawn 1:1, shifted by the Move-tool offset — see RasterFill docs.
        canvas.drawImageRect(
          action.image,
          Offset.zero & action.size,
          action.offset & action.size,
          Paint(),
        );
      } else if (action is Stroke) {
        _paintStroke(canvas, action, regions, scale, offset);
      }
    }

    final live = currentStroke;
    if (live != null) {
      _paintStroke(canvas, live, regions, scale, offset);
    }

    canvas.restore();

    // Color mode: SVG outline on top (kept outside the layer so erasing user
    // paint never wipes the line art). Draw mode already drew the guide below.
    if (paintMode == PaintMode.color) {
      template?.paintOutline(canvas, size);
    }

    // Selection highlight on top of everything (the brand primary box).
    final sel = selectionRect;
    if (sel != null) {
      const selColor = Color(0xFF6C5CE7);
      final box = RRect.fromRectAndRadius(
        sel.inflate(6),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.fill
          ..color = selColor.withValues(alpha: 0.08),
      );
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = selColor,
      );
      // Small corner handles.
      for (final c in [
        box.outerRect.topLeft,
        box.outerRect.topRight,
        box.outerRect.bottomLeft,
        box.outerRect.bottomRight,
      ]) {
        canvas.drawCircle(c, 4, Paint()..color = selColor);
      }
    }
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

    // Coloring strokes (not eraser) are clipped to the region containing their
    // first point, so colors stay inside the shape boundaries the artwork
    // implies. Eraser is unclipped — the user expects to erase across
    // boundaries. Free-draw / tracing strokes (`clipToRegions == false`) also
    // flow freely. A coloring stroke that *starts outside every region* (e.g.
    // on the blank background) is drawn unclipped rather than dropped, so the
    // user can draw anywhere on the page without switching modes.
    // A precomputed clip (outline-only coloring pages, flood-derived) wins; it's
    // already in canvas-space. Otherwise fall back to the active SVG's vector
    // regions (region SVGs), clipping to the one containing the stroke's start.
    final isColoringStroke =
        stroke.clipToRegions && stroke.tool != DrawingTool.eraser;
    Path? clipPath =
        stroke.tool != DrawingTool.eraser ? stroke.clipPath : null;
    if (clipPath == null && isColoringStroke && regions.isNotEmpty) {
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
      // Stay inside the lines: a coloring stroke whose first point landed
      // outside every region (e.g. begun on the blank background around the
      // artwork) has no shape to confine it. Drop it rather than drawing it
      // unclipped across the whole picture. Eraser and free-draw strokes
      // (clipToRegions == false) are unaffected and keep flowing freely.
      if (clipPath == null) return;
    }

    canvas.save();
    if (clipPath != null) {
      // Expand the clip path slightly so brush paint reaches the outline
      // edge — the exact path boundary leaves ~0.5px gaps from antialiasing,
      // making narrow regions look unfillable. A small scale transform lets
      // strokes color right up to the border without bleeding into adjacent
      // regions.
      final bounds = clipPath.getBounds();
      if (bounds.isFinite && bounds.width > 0 && bounds.height > 0) {
        final cx = bounds.center.dx;
        final cy = bounds.center.dy;
        final scale = 1.04; // 4% expansion (~2–4px on typical regions)
        final m = Matrix4.identity()
          ..translateByDouble(cx, cy, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1)
          ..translateByDouble(-cx, -cy, 0, 1);
        canvas.clipPath(clipPath.transform(m.storage));
      } else {
        canvas.clipPath(clipPath);
      }
    }

    if (canvasPoints.length == 1) {
      canvas.drawCircle(canvasPoints.first, canvasWidth / 2, paint);
    } else if (stroke.isShape) {
      // Recognized primitive: even-width path through the clean points, no
      // hand-drawn taper. `closed` joins the last point back to the first.
      canvas.drawPath(
        Path()..addPolygon(canvasPoints, stroke.closed),
        paint,
      );
    } else {
      _drawTaperedSmoothPath(canvas, canvasPoints, paint, canvasWidth);
    }

    canvas.restore();
  }

  /// Walks [points] and emits a single C1-continuous Path with cubic Bezier
  /// curves through every sample (Catmull-Rom-to-Bezier conversion with
  /// standard tension 1/6).  Unlike the previous per-segment approach, the
  /// entire stroke is a single [drawPath] call — no seam artifacts at segment
  /// boundaries.
  void _drawTaperedSmoothPath(
    Canvas canvas,
    List<Offset> points,
    Paint basePaint,
    double width,
  ) {
    if (points.length == 2) {
      canvas.drawLine(points[0], points[1], _makePaint(basePaint, width));
      return;
    }

    final path = _buildSmoothPath(points);
    canvas.drawPath(path, _makePaint(basePaint, width));
  }

  /// Catmull-Rom → Bezier for every span, building one continuous path.
  Path _buildSmoothPath(List<Offset> points) {
    final n = points.length;
    final path = Path()..moveTo(points[0].dx, points[0].dy);

    if (n == 2) {
      path.lineTo(points[1].dx, points[1].dy);
      return path;
    }

    for (var i = 0; i < n - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < n ? points[i + 2] : p2;

      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  Paint _makePaint(Paint source, double width) => Paint()
    ..color = source.color
    ..strokeWidth = width
    ..strokeCap = source.strokeCap
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = source.isAntiAlias
    ..maskFilter = source.maskFilter
    ..blendMode = source.blendMode;

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
      oldDelegate.template != template ||
      oldDelegate.paintMode != paintMode ||
      oldDelegate.backgroundImage != backgroundImage ||
      oldDelegate.selectionRect != selectionRect;
}
