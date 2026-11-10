import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A template (e.g. Heart, Star) that the user can paint inside.
///
/// The fill path is used to clip user strokes, so paint only appears inside
/// the shape — outside the path stays white. The outline is rendered on top
/// of the strokes so the shape boundary stays visible.
abstract class DrawingTemplate {
  const DrawingTemplate();

  String get name;
  IconData get icon;

  /// Natural coordinate space used to anchor user strokes to the artwork
  /// across canvas resizes (orientation changes, window resizes, etc.).
  ///
  /// Returning a non-null size opts the template into picture-space stroke
  /// storage: gestures get converted from canvas-space into this space before
  /// being recorded, and the painter converts back at draw time using the
  /// current `BoxFit.contain` transform. Templates that don't have a stable
  /// natural size (parametric shapes whose geometry follows the canvas) can
  /// leave this null and stay in canvas-space.
  Size? get naturalSize => null;

  /// `BoxFit.contain` transform from [naturalSize] into [canvasSize]:
  /// the picture is uniformly scaled by `scale` and offset by `offset`.
  /// Returns null when there's no natural size to fit against.
  ({Offset offset, double scale})? fitTransform(Size canvasSize) {
    final nat = naturalSize;
    if (nat == null || nat.isEmpty || canvasSize.isEmpty) return null;
    final scale = math.min(
      canvasSize.width / nat.width,
      canvasSize.height / nat.height,
    );
    final dx = (canvasSize.width - nat.width * scale) / 2;
    final dy = (canvasSize.height - nat.height * scale) / 2;
    return (offset: Offset(dx, dy), scale: scale);
  }

  /// Canvas-space → picture-space. Returns the input unchanged when the
  /// template has no [naturalSize].
  Offset canvasToPicture(Offset canvasPos, Size canvasSize) {
    final t = fitTransform(canvasSize);
    if (t == null) return canvasPos;
    return Offset(
      (canvasPos.dx - t.offset.dx) / t.scale,
      (canvasPos.dy - t.offset.dy) / t.scale,
    );
  }

  /// Picture-space → canvas-space.
  Offset pictureToCanvas(Offset picturePos, Size canvasSize) {
    final t = fitTransform(canvasSize);
    if (t == null) return picturePos;
    return Offset(
      picturePos.dx * t.scale + t.offset.dx,
      picturePos.dy * t.scale + t.offset.dy,
    );
  }

  /// Closed path describing the paintable interior, sized to [size].
  Path buildFillPath(Size size);

  /// Independent paintable sub-regions of the template.
  ///
  /// Each stroke is clipped to *one* region — the region containing the
  /// stroke's first point — so colors never bleed between regions. The
  /// default returns a single region equal to [buildFillPath], which gives
  /// the same behavior as before for simple single-region templates.
  List<Path> buildRegions(Size size) => [buildFillPath(size)];

  /// Strokes the visible outline over the user's painting.
  void paintOutline(Canvas canvas, Size size);

  /// Renders a thumbnail/preview of the template for the picker.
  ///
  /// Defaults to [paintOutline]; subclasses with a faster preview path
  /// (e.g. [ColoringPageTemplate], which can skip the per-frame `saveLayer`
  /// + multiply blend used to overlay user strokes) override this.
  void paintPreview(Canvas canvas, Size size) => paintOutline(canvas, size);

  /// Renders the artwork as a faint tracing guide *underneath* the user's
  /// strokes (PaintMode.draw). Unlike [paintOutline] this is drawn before the
  /// stroke layer so freehand strokes sit clearly on top of it.
  ///
  /// Defaults to [paintPreview]; subclasses override to control the opacity
  /// (see [ColoringPageTemplate]).
  void paintGuide(Canvas canvas, Size size) => paintPreview(canvas, size);
}
