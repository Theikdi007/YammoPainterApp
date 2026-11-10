import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../coloring/coloring_page_template.dart';
import '../coloring/parsing/coloring_page_loader.dart';
import '../models/drawing_template.dart';
import '../models/drawing_tool.dart';
import '../models/saved_drawing.dart';
import '../models/shape_recognizer.dart';
import '../models/stroke.dart';
import '../models/svg_asset.dart';
import '../services/saved_drawing_service.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/templates.dart';

/// Owns every piece of mutable state for the drawing screen.
///
/// Strokes and bucket fills share one time-ordered [actions] list so the
/// painter renders them in the order the user produced them. That ordering
/// matters for the eraser: an eraser stroke at index N only erases paint
/// from indices < N. A fill placed *after* an eraser stroke is fully
/// visible.
///
/// All actions are stored in picture-space (when a template is active) so
/// they stay anchored to the artwork across canvas resizes — the painter
/// applies the current `BoxFit.contain` transform at draw time.
class DrawingController extends GetxController {
  /// Time-ordered user actions: strokes (brush/eraser) and bucket fills.
  /// Oldest first; painter renders in order.
  final RxList<DrawAction> actions = <DrawAction>[].obs;

  /// In-flight stroke being drawn this very moment (one is set during a
  /// pan, null otherwise). Painter renders this *after* [actions] so the
  /// user sees the stroke as their finger moves, not only when they lift.
  final Rx<Stroke?> currentStroke = Rx<Stroke?>(null);

  /// Snapshots taken at the start of each user action so a single undo
  /// reverts that whole action (a stroke, a fill, a clear). Internal —
  /// callers only see [undo] / [redo] / [clearCanvas].
  final RxList<List<DrawAction>> _undoStack = <List<DrawAction>>[].obs;
  final RxList<List<DrawAction>> _redoStack = <List<DrawAction>>[].obs;

  final Rx<Color> selectedColor = const Color(0xFF000000).obs;
  final Rx<double> strokeWidth = 5.0.obs;

  /// Active tool — picks brush vs eraser for pan gestures, or bucket vs
  /// eyedropper for tap gestures.
  final Rx<DrawingTool> tool = DrawingTool.brush.obs;

  /// Visual variant of the brush. Painter maps this to a `Paint` setup.
  final Rx<BrushStyle> brushStyle = BrushStyle.round.obs;

  /// When on, a finished brush stroke that resembles a line / triangle /
  /// rectangle / circle is snapped to that clean (closed) shape — which also
  /// makes it fill cleanly with the bucket. Off by default now that the toolbar
  /// no longer exposes a toggle, so strokes stay true freehand; the recognizer
  /// only snaps clear shapes and passes anything ambiguous through, so it can
  /// still be flipped on programmatically without breaking ordinary scribbling.
  final RxBool autoShape = false.obs;

  void toggleAutoShape() => autoShape.value = !autoShape.value;

  /// Most-recently used custom colors, MRU-ordered, capped at 8.
  final RxList<Color> recentColors = <Color>[].obs;
  static const int _recentColorsCap = 8;

  /// Currently selected coloring-book template. `null` means free-draw mode
  /// (paint anywhere on the canvas).
  final Rx<DrawingTemplate?> selectedTemplate = Rx<DrawingTemplate?>(null);

  /// Render style for the canvas. With a picture active it's always
  /// [PaintMode.color] — line art crisp on top and bucket taps fill regions —
  /// while brush strokes still draw freely (clipping is decided per-stroke by
  /// the painter, so a stroke that starts inside a shape stays in the lines and
  /// one that starts on the blank background flows free). Free-draw (no
  /// template) is [PaintMode.draw]. Set automatically by [selectTemplate] /
  /// [startFreeDraw]; there's no longer a user-facing Draw/Color toggle.
  final Rx<PaintMode> paintMode = PaintMode.color.obs;

  /// A saved drawing loaded as a backdrop to "repaint" over (the Painting
  /// Recent tab). The painter draws it behind the strokes and the export
  /// includes it. Null in normal free-draw / coloring sessions.
  final Rx<ui.Image?> backgroundImage = Rx<ui.Image?>(null);

  /// The existing gallery entry currently being edited via "Repaint", or null
  /// for a fresh drawing. When set, [saveCurrentDrawing] overwrites this row in
  /// place instead of inserting a new one, so re-saving a repaint updates the
  /// original instead of piling up duplicates. Reset by every fresh-canvas entry
  /// point (free draw / picking a template); set by [repaintFromUrl].
  SavedDrawing? _editingTarget;

  /// Whether the current session is editing an existing saved drawing (Repaint).
  bool get isEditingSaved => _editingTarget != null;

  /// The name of the editing target, or null for a fresh drawing.
  String? get editingTargetName => _editingTarget?.name;

  /// The saved drawing being edited (Repaint), or null for a fresh drawing.
  SavedDrawing? get editingTarget => _editingTarget;

  /// Callback the Library registers so that saving a drawing (deep in the
  /// canvas / result screens) refreshes the Library's "Your drawings" row when
  /// the user returns. Null when the Library isn't mounted.
  void Function()? onDrawingSaved;

  /// Index into [actions] of the element the user long-pressed to select, or
  /// null. The selected element shows a highlight and can be dragged to move or
  /// duplicated; any new stroke / undo / clear drops the selection.
  final Rx<int?> selectedIndex = Rx<int?>(null);

  /// Last canvas size seen during a gesture — lets [duplicateSelected] (driven
  /// by a toolbar button, with no gesture context) offset the copy correctly.
  Size canvasSize = Size.zero;

  /// Whether a still-valid element is selected.
  bool get hasSelection {
    final i = selectedIndex.value;
    return i != null && i >= 0 && i < actions.length;
  }

  /// True only in a blank free-draw session — no coloring template and no
  /// backdrop image (repaint / color-over a picture). The selection, move,
  /// duplicate and shape-snap tools are limited to this mode; when coloring a
  /// picture or template they're hidden/disabled. Reads the underlying `Rx`
  /// values so it stays reactive inside `Obx`.
  bool get isFreeDraw =>
      selectedTemplate.value == null && backgroundImage.value == null;

  // Lazily snapshot for undo on the first real move of a selection drag, so a
  // select-without-move doesn't waste an undo step.
  bool _moveSnapshotted = false;

  /// Wraps the canvas so we can rasterize it for [renderCanvasPng] (and for the
  /// eyedropper pixel-sampling fallback).
  final GlobalKey repaintBoundaryKey = GlobalKey();

  /// Drives the [InteractiveViewer] around the canvas.
  final TransformationController transformationController =
      TransformationController();

  void resetZoom() {
    transformationController.value = Matrix4.identity();
  }

  @override
  void onClose() {
    transformationController.dispose();
    backgroundImage.value?.dispose();
    super.onClose();
  }

  /// Swaps the repaint backdrop, disposing the previous image so we don't leak
  /// decoded bitmaps as the user opens different saved drawings.
  void _setBackgroundImage(ui.Image? image) {
    final old = backgroundImage.value;
    if (old == image) return;
    backgroundImage.value = image;
    old?.dispose();
  }

  // ---------------------------------------------------------------------------
  // Gesture handling — pan = brush/eraser, tap = bucket/eyedropper.
  // ---------------------------------------------------------------------------

  /// Picture-space points accumulated for the in-flight pan stroke. Mirrors
  /// [currentStroke.value.points] but is also the buffer mutated on every
  /// pan update — we re-emit a fresh [Stroke] from this list each time so
  /// `Rx` reactivity fires and the painter renders the partial stroke
  /// before `panEnd`.
  final List<Offset> _currentStrokePoints = <Offset>[];

  /// Stroke meta captured at stroke start so mid-stroke tool/color/width
  /// changes don't retroactively rewrite the in-flight stroke.
  bool _currentStrokeIsPictureSpace = false;
  double _currentStrokeWidth = 0;
  Color _currentStrokeColor = const Color(0xFF000000);
  DrawingTool _currentStrokeTool = DrawingTool.brush;
  BrushStyle _currentStrokeStyle = BrushStyle.round;
  bool _currentStrokeClip = false;

  /// Canvas-space clip for the in-flight stroke on an outline-only coloring page
  /// (flood-derived; see [_maybeRegionClip]). Null for region SVGs / free-draw.
  Path? _currentStrokeClipPath;

  // Low-res raster of the active coloring page's line art, captured once per
  // template. Used to flood-fill the bounded region under the brush so strokes
  // stay inside the lines on outline-only SVGs (which expose no vector regions).
  Uint8List? _baselineRgba;
  int _baselineW = 0;
  int _baselineH = 0;
  bool _baselineCapturing = false;

  /// Cached "this template has no vector fill regions" (outline-only line art),
  /// so a region-clip flood is only attempted when it's actually needed. Reset
  /// whenever the template changes.
  bool? _coloringOutlineOnly;

  /// Monotonic id for the in-flight stroke, so a deferred region-clip (captured
  /// asynchronously for the very first stroke) only applies if that same stroke
  /// is still the current/last one.
  int _strokeSeq = 0;

  /// Move-tool drag state: index of the grabbed action and the last pointer
  /// position (canvas-space). Null when not dragging an element.
  int? _moveIndex;
  Offset? _moveLast;

  bool get _toolIsPan =>
      tool.value == DrawingTool.brush || tool.value == DrawingTool.eraser;

  /// Builds an immutable snapshot of the in-flight stroke. Called whenever
  /// [_currentStrokePoints] changes so the painter can render it.
  Stroke _emitCurrentStroke() {
    return Stroke(
      tool: _currentStrokeTool,
      style: _currentStrokeStyle,
      color: _currentStrokeColor,
      width: _currentStrokeWidth,
      points: List<Offset>.from(_currentStrokePoints),
      isPictureSpace: _currentStrokeIsPictureSpace,
      clipToRegions: _currentStrokeClip,
      clipPath: _currentStrokeClipPath,
    );
  }

  void handlePanStart(DragStartDetails details, Size canvasSize) {
    if (tool.value == DrawingTool.move) {
      _moveStart(details.localPosition, canvasSize);
      return;
    }
    if (!_toolIsPan) return;

    clearSelection(); // starting a new stroke drops any selection
    _snapshotForUndo();
    _redoStack.clear();

    final template = selectedTemplate.value;
    final fit = template?.fitTransform(canvasSize);
    if (fit == null) {
      _currentStrokeIsPictureSpace = false;
      _currentStrokeWidth = strokeWidth.value;
      _currentStrokePoints
        ..clear()
        ..add(details.localPosition);
    } else {
      _currentStrokeIsPictureSpace = true;
      _currentStrokeWidth = strokeWidth.value / fit.scale;
      _currentStrokePoints
        ..clear()
        ..add(template!.canvasToPicture(details.localPosition, canvasSize));
    }
    _currentStrokeColor = selectedColor.value;
    _currentStrokeTool = tool.value;
    _currentStrokeStyle = brushStyle.value;
    // With a picture or repaint backdrop active, the painter clips a stroke to
    // the region containing its first point (stay in the lines) but draws strokes
    // that start on the blank background freely — so you can color and draw
    // without a mode toggle. Captured per-stroke so it's stable.
    _currentStrokeClip = template != null || backgroundImage.value != null;
    // Outline-only coloring pages have no vector regions for the painter to clip
    // against, so flood the bounded area under the finger and clip the brush to
    // it — keeping paint inside the black lines just like the fill tool.
    _strokeSeq++;
    _currentStrokeClipPath = _maybeRegionClip(details.localPosition, canvasSize);
    currentStroke.value = _emitCurrentStroke();
  }

  void handlePanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (tool.value == DrawingTool.move) {
      _moveUpdate(details.localPosition, canvasSize);
      return;
    }
    if (!_toolIsPan || _currentStrokePoints.isEmpty) return;
    final template = selectedTemplate.value;
    final fit = template?.fitTransform(canvasSize);
    final p = (fit == null)
        ? details.localPosition
        : template!.canvasToPicture(details.localPosition, canvasSize);
    // Skip points within ~2px of the last one to reduce touch jitter.
    // This produces much smoother curves — Catmull-Rom interpolation
    // works best with well-spaced samples.
    if (_currentStrokePoints.isNotEmpty &&
        (p - _currentStrokePoints.last).distanceSquared < 4.0) {
      return;
    }
    _currentStrokePoints.add(p);
    // Re-emit a fresh Stroke so Rx fires and the painter sees the new
    // point. Re-using the same object wouldn't trigger reactivity.
    currentStroke.value = _emitCurrentStroke();
  }

  void handlePanEnd(DragEndDetails details) {
    if (tool.value == DrawingTool.move) {
      _moveEnd();
      return;
    }
    if (!_toolIsPan || _currentStrokePoints.isEmpty) return;
    actions.add(_finishStroke());
    _currentStrokePoints.clear();
    currentStroke.value = null;
  }

  /// Builds the stroke to commit. With [autoShape] on, a brush stroke that
  /// matches a primitive is replaced by the clean shape; otherwise the freehand
  /// stroke is kept as-is.
  Stroke _finishStroke() {
    if (autoShape.value && _currentStrokeTool == DrawingTool.brush) {
      final shape = recognizeShape(_currentStrokePoints);
      if (shape != null) {
        return Stroke(
          tool: _currentStrokeTool,
          style: _currentStrokeStyle,
          color: _currentStrokeColor,
          width: _currentStrokeWidth,
          points: shape.points,
          isPictureSpace: _currentStrokeIsPictureSpace,
          clipToRegions: _currentStrokeClip,
          clipPath: _currentStrokeClipPath,
          isShape: true,
          closed: shape.closed,
        );
      }
    }
    return _emitCurrentStroke();
  }

  /// Aborts the in-flight stroke (if any) without committing it. Called when
  /// a second finger touches down so a pinch-zoom can take over without
  /// leaving a stray scribble behind. Also rolls back the undo snapshot
  /// pushed in [handlePanStart] so the abort doesn't waste an undo step.
  void cancelStroke() {
    if (_currentStrokePoints.isEmpty && currentStroke.value == null) return;
    _currentStrokePoints.clear();
    currentStroke.value = null;
    if (_undoStack.isNotEmpty) {
      _undoStack.removeLast();
    }
  }

  // ---------------------------------------------------------------------------
  // Move tool — drag a single element (stroke / fill) under the finger.
  // ---------------------------------------------------------------------------

  void _moveStart(Offset p, Size canvasSize) {
    final fit = selectedTemplate.value?.fitTransform(canvasSize);
    _moveLast = p;
    _moveIndex = _hitTestTopmost(p, fit, canvasSize);
    // Snapshot once at grab time so the whole drag is a single undo step.
    if (_moveIndex != null) {
      _snapshotForUndo();
      _redoStack.clear();
    }
  }

  void _moveUpdate(Offset p, Size canvasSize) {
    final idx = _moveIndex;
    final last = _moveLast;
    if (idx == null || last == null) return;
    final delta = p - last;
    if (delta == Offset.zero) return;
    _moveLast = p;
    final fit = selectedTemplate.value?.fitTransform(canvasSize);
    // Replacing the element with a translated copy fires RxList reactivity.
    actions[idx] = _translateAction(actions[idx], delta, fit);
  }

  void _moveEnd() {
    _moveIndex = null;
    _moveLast = null;
  }

  /// Topmost (most recently drawn) action whose geometry contains [p], or null.
  int? _hitTestTopmost(
    Offset p,
    ({Offset offset, double scale})? fit,
    Size canvasSize,
  ) {
    for (var i = actions.length - 1; i >= 0; i--) {
      if (_actionHit(actions[i], p, fit)) return i;
    }
    return null;
  }

  bool _actionHit(
    DrawAction action,
    Offset p,
    ({Offset offset, double scale})? fit,
  ) {
    if (action is Stroke) {
      Rect? bounds;
      for (final pt in action.points) {
        final c = (action.isPictureSpace && fit != null)
            ? Offset(pt.dx * fit.scale + fit.offset.dx,
                pt.dy * fit.scale + fit.offset.dy)
            : pt;
        final r = Rect.fromLTWH(c.dx, c.dy, 0, 0);
        bounds = bounds == null ? r : bounds.expandToInclude(r);
      }
      if (bounds == null) return false;
      final widthCanvas = (action.isPictureSpace && fit != null)
          ? action.width * fit.scale
          : action.width;
      return bounds.inflate(widthCanvas / 2 + 12).contains(p);
    }
    if (action is BucketFill) {
      final region = (action.isPictureSpace && fit != null)
          ? action.region.transform(_pictureToCanvas(fit).storage)
          : action.region;
      return region.contains(p);
    }
    if (action is RasterFill) {
      final base = action.bounds ?? (Offset.zero & action.size);
      return base.shift(action.offset).contains(p);
    }
    return false;
  }

  DrawAction _translateAction(
    DrawAction action,
    Offset deltaCanvas,
    ({Offset offset, double scale})? fit,
  ) {
    Offset toSpace(bool isPictureSpace) =>
        (isPictureSpace && fit != null && fit.scale != 0)
            ? Offset(deltaCanvas.dx / fit.scale, deltaCanvas.dy / fit.scale)
            : deltaCanvas;

    if (action is Stroke) {
      final d = toSpace(action.isPictureSpace);
      return Stroke(
        tool: action.tool,
        style: action.style,
        color: action.color,
        width: action.width,
        points: [for (final pt in action.points) pt + d],
        isPictureSpace: action.isPictureSpace,
        clipToRegions: action.clipToRegions,
        isShape: action.isShape,
        closed: action.closed,
      );
    }
    if (action is BucketFill) {
      final d = toSpace(action.isPictureSpace);
      return BucketFill(
        region: action.region.shift(d),
        color: action.color,
        isPictureSpace: action.isPictureSpace,
      );
    }
    if (action is RasterFill) {
      return RasterFill(
        image: action.image,
        size: action.size,
        offset: action.offset + deltaCanvas,
        bounds: action.bounds,
      );
    }
    return action;
  }

  // ---------------------------------------------------------------------------
  // Selection — long-press to select an element, then drag to move / duplicate.
  // ---------------------------------------------------------------------------

  void clearSelection() {
    if (selectedIndex.value != null) selectedIndex.value = null;
  }

  /// Selects the topmost element under [p] (or clears the selection if none).
  /// Returns whether something was selected.
  bool selectAt(Offset p, Size size) {
    canvasSize = size;
    final fit = selectedTemplate.value?.fitTransform(size);
    final idx = _hitTestTopmost(p, fit, size);
    selectedIndex.value = idx;
    return idx != null;
  }

  /// Whether [p] lands on the currently selected element, so a drag starting
  /// there should move it instead of painting.
  bool selectedContains(Offset p, Size size) {
    final idx = selectedIndex.value;
    if (idx == null || idx >= actions.length) return false;
    final fit = selectedTemplate.value?.fitTransform(size);
    return _actionHit(actions[idx], p, fit);
  }

  /// Begins dragging the selected element. The undo snapshot is deferred to the
  /// first real move (see [updateMoveSelected]).
  void beginMoveSelected(Offset p, Size size) {
    final idx = selectedIndex.value;
    if (idx == null || idx >= actions.length) return;
    canvasSize = size;
    _moveIndex = idx;
    _moveLast = p;
    _moveSnapshotted = false;
  }

  void updateMoveSelected(Offset p, Size size) {
    final idx = _moveIndex;
    final last = _moveLast;
    if (idx == null || last == null) return;
    final delta = p - last;
    if (delta == Offset.zero) return;
    if (!_moveSnapshotted) {
      _snapshotForUndo();
      _redoStack.clear();
      _moveSnapshotted = true;
    }
    _moveLast = p;
    final fit = selectedTemplate.value?.fitTransform(size);
    actions[idx] = _translateAction(actions[idx], delta, fit);
  }

  void endMoveSelected() {
    _moveIndex = null;
    _moveLast = null;
    _moveSnapshotted = false;
  }

  /// Duplicates the selected element, offset slightly so the copy is visible;
  /// the copy becomes the new selection (ready to drag).
  void duplicateSelected() {
    final idx = selectedIndex.value;
    if (idx == null || idx >= actions.length) return;
    _snapshotForUndo();
    _redoStack.clear();
    final fit = selectedTemplate.value?.fitTransform(canvasSize);
    actions.add(_translateAction(actions[idx], const Offset(28, 28), fit));
    selectedIndex.value = actions.length - 1;
  }

  /// Canvas-space bounding box of the selected element, for the highlight box.
  Rect? selectionRect(Size size) {
    final idx = selectedIndex.value;
    if (idx == null || idx >= actions.length) return null;
    final fit = selectedTemplate.value?.fitTransform(size);
    return _actionBounds(actions[idx], fit);
  }

  Rect? _actionBounds(DrawAction action, ({Offset offset, double scale})? fit) {
    if (action is Stroke) {
      Rect? b;
      for (final pt in action.points) {
        final c = (action.isPictureSpace && fit != null)
            ? Offset(pt.dx * fit.scale + fit.offset.dx,
                pt.dy * fit.scale + fit.offset.dy)
            : pt;
        final r = Rect.fromLTWH(c.dx, c.dy, 0, 0);
        b = b == null ? r : b.expandToInclude(r);
      }
      if (b == null) return null;
      final w = (action.isPictureSpace && fit != null)
          ? action.width * fit.scale
          : action.width;
      return b.inflate(w / 2 + 4);
    }
    if (action is BucketFill) {
      final region = (action.isPictureSpace && fit != null)
          ? action.region.transform(_pictureToCanvas(fit).storage)
          : action.region;
      return region.getBounds();
    }
    if (action is RasterFill) {
      final base = action.bounds ?? (Offset.zero & action.size);
      return base.shift(action.offset);
    }
    return null;
  }

  Matrix4 _pictureToCanvas(({Offset offset, double scale}) fit) =>
      Matrix4.identity()
        ..translateByDouble(fit.offset.dx, fit.offset.dy, 0, 1)
        ..scaleByDouble(fit.scale, fit.scale, 1, 1);

  /// Tap-driven tools. A brush / eraser tap drops a single dot (so tapping
  /// anywhere leaves a mark); bucket fills and the eyedropper sample.
  Future<void> handleTap(Offset localPosition, Size canvasSize) async {
    switch (tool.value) {
      case DrawingTool.bucket:
        await _bucketAt(localPosition, canvasSize);
      case DrawingTool.eyedropper:
        await _eyedropAt(localPosition, canvasSize);
      case DrawingTool.brush:
      case DrawingTool.eraser:
        _dabAt(localPosition, canvasSize);
      case DrawingTool.move:
        return;
    }
  }

  /// Commits a one-point stroke at [localPosition] — the painter renders a
  /// single-point stroke as a filled circle, so a brush tap leaves a dot (and
  /// an eraser tap rubs out a dot). Snapshots first so it's a single undo step.
  void _dabAt(Offset localPosition, Size canvasSize) {
    clearSelection();
    _snapshotForUndo();
    _redoStack.clear();

    final template = selectedTemplate.value;
    final fit = template?.fitTransform(canvasSize);
    final Offset point;
    final double width;
    final bool isPictureSpace;
    if (fit == null) {
      point = localPosition;
      width = strokeWidth.value;
      isPictureSpace = false;
    } else {
      point = template!.canvasToPicture(localPosition, canvasSize);
      width = strokeWidth.value / fit.scale;
      isPictureSpace = true;
    }

    actions.add(
      Stroke(
        tool: tool.value,
        style: brushStyle.value,
        color: selectedColor.value,
        width: width,
        points: [point],
        isPictureSpace: isPictureSpace,
        clipToRegions: template != null,
      ),
    );
  }

  /// Routes a bucket tap: when coloring an SVG picture, fill its vector region;
  /// otherwise (free-draw or tracing) raster-flood-fill within the strokes the
  /// user drew.
  Future<void> _bucketAt(Offset localPosition, Size canvasSize) async {
    final template = selectedTemplate.value;
    if (template != null && paintMode.value == PaintMode.color) {
      // Prefer vector region fill (crisp) when the SVG has closed regions.
      // Outline-only coloring pages have none, so fall through to raster
      // flood-fill — the SVG line art is rendered crisply on the canvas, so the
      // flood stays neatly within the black lines. This makes *any* SVG
      // coloring page fillable.
      if (_bucketFillAt(localPosition, canvasSize)) return;
    }
    await _rasterFloodFillAt(localPosition, canvasSize);
  }

  /// Flood-fills the area around [localPosition] that is bounded by drawn
  /// strokes, for free-draw / tracing where there are no vector regions.
  ///
  /// Rasterizes the canvas (same boundary the eyedropper samples), runs a
  /// 4-connected flood fill over pixels matching the tapped color, and stores
  /// the result as a [RasterFill] bitmap. Captured at `pixelRatio: 1.0` so the
  /// image dimensions equal the logical canvas size and draw back 1:1.
  Future<void> _rasterFloodFillAt(Offset localPosition, Size canvasSize) async {
    final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;

    ui.Image snapshot;
    try {
      snapshot = await boundary.toImage(pixelRatio: 1.0);
    } catch (_) {
      return;
    }
    final w = snapshot.width;
    final h = snapshot.height;
    final byteData =
        await snapshot.toByteData(format: ui.ImageByteFormat.rawRgba);
    snapshot.dispose();
    if (byteData == null) return;
    final src = byteData.buffer.asUint8List();

    final sx = localPosition.dx.clamp(0, w - 1).toInt();
    final sy = localPosition.dy.clamp(0, h - 1).toInt();
    final seed = (sy * w + sx) * 4;
    final tr = src[seed], tg = src[seed + 1], tb = src[seed + 2], ta = src[seed + 3];

    // Fill color (opaque — kids color with solid colors).
    final argb = selectedColor.value.toARGB32();
    final fr = (argb >> 16) & 0xFF;
    final fg = (argb >> 8) & 0xFF;
    final fb = argb & 0xFF;

    // No-op if the tapped pixel already matches the fill color.
    if (_closeColor(tr, tg, tb, ta, fr, fg, fb, 255, 8)) return;

    const tolerance = 56; // forgiving enough to cross anti-aliased gaps
    final out = Uint8List(w * h * 4); // transparent by default
    final visited = Uint8List(w * h);
    final stack = <int>[sy * w + sx];
    visited[sy * w + sx] = 1;

    // Tight bounds of the filled pixels, for Move hit-testing.
    var minFx = sx, maxFx = sx, minFy = sy, maxFy = sy;

    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final o = p * 4;
      out[o] = fr;
      out[o + 1] = fg;
      out[o + 2] = fb;
      out[o + 3] = 255;

      final x = p % w;
      final y = p ~/ w;
      if (x < minFx) minFx = x;
      if (x > maxFx) maxFx = x;
      if (y < minFy) minFy = y;
      if (y > maxFy) maxFy = y;
      void consider(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) return;
        final np = ny * w + nx;
        if (visited[np] == 1) return;
        final no = np * 4;
        if (!_closeColor(
          src[no], src[no + 1], src[no + 2], src[no + 3],
          tr, tg, tb, ta,
          tolerance,
        )) {
          return;
        }
        visited[np] = 1;
        stack.add(np);
      }

      consider(x - 1, y);
      consider(x + 1, y);
      consider(x, y - 1);
      consider(x, y + 1);
    }

    final filled = await _imageFromRgba(out, w, h);
    _snapshotForUndo();
    _redoStack.clear();
    actions.add(
      RasterFill(
        image: filled,
        size: Size(w.toDouble(), h.toDouble()),
        bounds: Rect.fromLTRB(
          minFx.toDouble(),
          minFy.toDouble(),
          (maxFx + 1).toDouble(),
          (maxFy + 1).toDouble(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Region-bounded brush for outline-only coloring pages
  // ---------------------------------------------------------------------------

  void _resetColoringBaseline() {
    _baselineRgba = null;
    _baselineW = 0;
    _baselineH = 0;
    _baselineCapturing = false;
    _coloringOutlineOnly = null;
  }

  /// Captures a low-res raster of the current canvas once, to flood region
  /// clips against. Works for:
  /// - coloring pages (SVG template is set)
  /// - repaint mode (a [backgroundImage] is set but no template)
  ///
  /// Skips until the frame has actually rendered (captured frame contains dark
  /// pixels), so something that paints a frame late doesn't lock in a blank
  /// baseline. Safe to call every frame — it no-ops once captured. Called from
  /// the canvas after layout.
  Future<void> ensureColoringBaseline(Size canvasSize) async {
    if (_baselineRgba != null || _baselineCapturing) return;
    // Need either a template (coloring page) or a repaint background.
    if (selectedTemplate.value == null && backgroundImage.value == null) {
      return;
    }
    final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    _baselineCapturing = true;
    try {
      // Capture near full resolution (phones) so line boundaries stay crisp and
      // the flood doesn't leak across thin lines; only very large canvases
      // (tablets) downsample, to keep the flood + clip path affordable.
      final longest = canvasSize.longestSide;
      final ratio = longest > 1280 ? 1280 / longest : 1.0;
      final img = await boundary.toImage(pixelRatio: ratio);
      final w = img.width;
      final h = img.height;
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (byteData == null) return;
      final pixels = byteData.buffer.asUint8List();
      // Don't accept a blank (no line art yet) frame — let a later frame retry.
      var hasDark = false;
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i] < 90 && pixels[i + 1] < 90 && pixels[i + 2] < 90) {
          hasDark = true;
          break;
        }
      }
      if (!hasDark) return;
      _baselineRgba = pixels;
      _baselineW = w;
      _baselineH = h;
    } catch (_) {
      // leave baseline unset; a later frame retries
    } finally {
      _baselineCapturing = false;
    }
  }

  /// For a brush stroke, returns a canvas-space clip path confining it to the
  /// bounded region under [canvasPoint], or null when clipping shouldn't apply.
  ///
  /// Handles three scenarios:
  /// - **Coloring page with vector regions** — the painter clips via the SVG's
  ///   vector paths; flood clip is not needed (returns null).
  /// - **Outline-only SVG (regions empty)** — flood-fills the bounded area in
  ///   the cached line-art baseline, same as repaint mode below.
  /// - **Repaint mode** (no template, [backgroundImage] set) — flood-fills the
  ///   backdrop image to keep brush paint inside the artwork boundaries.
  Path? _maybeRegionClip(Offset canvasPoint, Size canvasSize) {
    if (_currentStrokeTool != DrawingTool.brush) return null;
    final template = selectedTemplate.value;
    final bg = backgroundImage.value;
    // Pure free-draw: no template and no backdrop → no clipping.
    if (template == null && bg == null) return null;
    // When a template is active, skip flood-clip for region SVGs (the painter
    // clips via vector paths); only outline-only line art needs the flood.
    if (template != null) {
      if (paintMode.value != PaintMode.color) return null;
      _coloringOutlineOnly ??= template.buildRegions(canvasSize).isEmpty;
      if (_coloringOutlineOnly != true) return null;
    }
    if (_baselineRgba == null) {
      // Baseline not captured yet (typically the very first stroke): capture it
      // and apply the clip to this stroke once ready, so even the first stroke
      // ends up confined to its region.
      _deferRegionClip(canvasPoint, canvasSize, _strokeSeq);
      return null;
    }
    return _floodClipPath(canvasPoint, canvasSize);
  }

  /// Captures the baseline then clips the still-current (or just-committed)
  /// stroke to its region. Used when the baseline wasn't ready at stroke start.
  Future<void> _deferRegionClip(
    Offset canvasPoint,
    Size canvasSize,
    int id,
  ) async {
    // The baseline may still be capturing (post-frame, in flight); poll briefly
    // until it lands or this stroke is superseded.
    for (var i = 0; i < 20 && _baselineRgba == null && id == _strokeSeq; i++) {
      await ensureColoringBaseline(canvasSize);
      if (_baselineRgba != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (id != _strokeSeq || _baselineRgba == null) return; // superseded/failed
    final path = _floodClipPath(canvasPoint, canvasSize);
    if (path == null || id != _strokeSeq) return;
    _currentStrokeClipPath = path;
    if (_currentStrokePoints.isNotEmpty) {
      // Still drawing → update the live preview so it clips immediately.
      currentStroke.value = _emitCurrentStroke();
    } else if (actions.isNotEmpty && actions.last is Stroke) {
      // Already committed → swap in a clipped copy of the last stroke.
      actions[actions.length - 1] = _withClipPath(actions.last as Stroke, path);
    }
  }

  Stroke _withClipPath(Stroke s, Path clip) => Stroke(
        tool: s.tool,
        style: s.style,
        color: s.color,
        width: s.width,
        points: s.points,
        isPictureSpace: s.isPictureSpace,
        clipToRegions: s.clipToRegions,
        clipPath: clip,
        isShape: s.isShape,
        closed: s.closed,
      );

  /// Flood-fills the bounded area at [canvasPoint] in the cached line-art
  /// baseline and returns it as a canvas-space clip path (scanline rectangles).
  /// Null when the seed floods most of the canvas (the open background) or the
  /// region is degenerate.
  Path? _floodClipPath(Offset canvasPoint, Size canvasSize) {
    final src = _baselineRgba;
    if (src == null) return null;
    final w = _baselineW;
    final h = _baselineH;
    final sx = (canvasPoint.dx / canvasSize.width * w).clamp(0, w - 1).toInt();
    final sy = (canvasPoint.dy / canvasSize.height * h).clamp(0, h - 1).toInt();
    final seed = (sy * w + sx) * 4;
    final tr = src[seed], tg = src[seed + 1], tb = src[seed + 2];
    final ta = src[seed + 3];

    const tolerance = 56;
    final visited = Uint8List(w * h);
    final stack = <int>[sy * w + sx];
    visited[sy * w + sx] = 1;
    var minX = sx, maxX = sx, minY = sy, maxY = sy;
    var count = 0;

    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      count++;
      final x = p % w;
      final y = p ~/ w;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      void consider(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) return;
        final np = ny * w + nx;
        if (visited[np] == 1) return;
        final no = np * 4;
        if (!_closeColor(
          src[no], src[no + 1], src[no + 2], src[no + 3],
          tr, tg, tb, ta,
          tolerance,
        )) {
          return;
        }
        visited[np] = 1;
        stack.add(np);
      }

      consider(x - 1, y);
      consider(x + 1, y);
      consider(x, y - 1);
      consider(x, y + 1);
    }

    // Seed was on the open background (or a tiny speck) — don't clip.
    if (count < 6 || count > w * h * 0.8) return null;

    // Build the clip from horizontal pixel runs, scaled back to canvas space.
    final scaleX = canvasSize.width / w;
    final scaleY = canvasSize.height / h;
    final path = Path();
    for (var y = minY; y <= maxY; y++) {
      var x = minX;
      while (x <= maxX) {
        if (visited[y * w + x] == 1) {
          final runStart = x;
          while (x <= maxX && visited[y * w + x] == 1) {
            x++;
          }
          path.addRect(
            Rect.fromLTRB(runStart * scaleX, y * scaleY, x * scaleX,
                (y + 1) * scaleY),
          );
        } else {
          x++;
        }
      }
    }
    return path;
  }

  /// Per-channel closeness test used by the flood fill (max channel delta
  /// within [tol]). Alpha is compared too so transparent edges aren't crossed.
  bool _closeColor(
    int r1, int g1, int b1, int a1,
    int r2, int g2, int b2, int a2,
    int tol,
  ) {
    return (r1 - r2).abs() <= tol &&
        (g1 - g2).abs() <= tol &&
        (b1 - b2).abs() <= tol &&
        (a1 - a2).abs() <= tol;
  }

  /// Decodes an RGBA byte buffer into a [ui.Image] for the painter to draw.
  Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Vector region fill for SVG coloring pages with closed fill regions. Returns
  /// `true` if it filled a region, `false` when the SVG has no usable region at
  /// the tap (e.g. outline-only line art) so the caller can fall back.
  bool _bucketFillAt(Offset localPosition, Size canvasSize) {
    final template = selectedTemplate.value;
    if (template == null) return false;
    final regions = template.buildRegions(canvasSize);
    if (regions.isEmpty) return false;

    // Smallest region that contains the tap wins — mirrors the painter's
    // per-stroke clip rule, so a tap inside a flower's center colors the
    // center, not the whole flower silhouette underneath.
    Path? hit;
    double? bestArea;
    for (final region in regions) {
      if (!region.contains(localPosition)) continue;
      final b = region.getBounds();
      final area = b.width * b.height;
      if (bestArea == null || area < bestArea) {
        bestArea = area;
        hit = region;
      }
    }
    if (hit == null) return false;

    _snapshotForUndo();
    _redoStack.clear();

    // Convert the canvas-space region path to picture-space so the fill
    // anchors to the artwork on resize. Picture-to-canvas is
    //     canvas = picture * scale + offset
    // so the inverse applied to the canvas-space hit path is
    //     picture = (canvas - offset) / scale
    // i.e. translate(-offset) then scale(1/scale).
    final fit = template.fitTransform(canvasSize);
    Path stored = hit;
    bool isPictureSpace = false;
    if (fit != null && fit.scale > 0) {
      final invScale = 1.0 / fit.scale;
      final m = Matrix4.identity()
        ..scaleByDouble(invScale, invScale, 1, 1)
        ..translateByDouble(-fit.offset.dx, -fit.offset.dy, 0, 1);
      stored = hit.transform(m.storage);
      isPictureSpace = true;
    }

    actions.add(
      BucketFill(
        region: stored,
        color: selectedColor.value,
        isPictureSpace: isPictureSpace,
      ),
    );
    return true;
  }

  Future<void> _eyedropAt(Offset localPosition, Size canvasSize) async {
    final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;

    try {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final w = image.width;
      final h = image.height;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final px = localPosition.dx.clamp(0, w - 1).toInt();
      final py = localPosition.dy.clamp(0, h - 1).toInt();
      final idx = (py * w + px) * 4;
      if (idx + 3 >= bytes.length) return;
      final sampled = Color.fromARGB(
        bytes[idx + 3],
        bytes[idx],
        bytes[idx + 1],
        bytes[idx + 2],
      );
      // White / transparent samples often mean the user tapped a blank
      // area; fall back to the SVG region's recorded fill when available.
      final argb = sampled.toARGB32();
      final a = (argb >> 24) & 0xFF;
      final r = (argb >> 16) & 0xFF;
      final g = (argb >> 8) & 0xFF;
      final b = argb & 0xFF;
      if (a < 32 || (r > 240 && g > 240 && b > 240)) {
        _eyedropFromSvgFallback(localPosition, canvasSize);
        return;
      }
      selectColor(_opaque(sampled));
    } catch (_) {
      _eyedropFromSvgFallback(localPosition, canvasSize);
    }
  }

  /// Fallback when raster sampling fails (or the user tapped a transparent
  /// pixel): use the SVG region's recorded fill color.
  void _eyedropFromSvgFallback(Offset localPosition, Size canvasSize) {
    final template = selectedTemplate.value;
    if (template is! ColoringPageTemplate) return;
    final regions = template.buildRegions(canvasSize);
    final fills = template.page.regionFills;
    if (regions.length != fills.length) return;
    for (var i = 0; i < regions.length; i++) {
      if (!regions[i].contains(localPosition)) continue;
      final c = fills[i];
      if (c != null) {
        selectColor(_opaque(c));
        return;
      }
    }
  }

  Color _opaque(Color c) {
    final argb = c.toARGB32();
    return Color.fromARGB(0xFF, (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
  }

  // ---------------------------------------------------------------------------
  // Tool / palette selection
  // ---------------------------------------------------------------------------

  void selectColor(Color color) {
    selectedColor.value = color;
    _pushRecentColor(color);
  }

  void selectTool(DrawingTool t) {
    clearSelection(); // switching tools drops the selection + its highlight
    tool.value = t;
  }

  void selectBrushStyle(BrushStyle s) {
    brushStyle.value = s;
  }

  void setStrokeWidth(double width) => strokeWidth.value = width;

  void selectTemplate(DrawingTemplate? template) {
    // Switching to a different template should start fresh — picture-space
    // strokes from the previous template would otherwise overlay the new
    // artwork (same viewBox = same coordinates). Picking the *same*
    // template again is a no-op, so the user can re-tap it without losing
    // their work.
    if (selectedTemplate.value != template &&
        (actions.isNotEmpty || currentStroke.value != null)) {
      _undoStack.clear();
      _redoStack.clear();
      actions.clear();
      currentStroke.value = null;
    }
    selectedTemplate.value = template;
    clearSelection();
    // New artwork ⇒ the line-art baseline used for region-bounded brushing is
    // stale; recapture lazily for the new page.
    _resetColoringBaseline();
    // Choosing a template (or going blank) leaves the repaint backdrop — and the
    // edit-in-place target — behind: this is a fresh drawing, not an edit.
    _setBackgroundImage(null);
    _editingTarget = null;
    // Auto shape-snap is for free drawing only; off when coloring inside a
    // picture so coloring strokes aren't snapped to primitives.
    autoShape.value = template == null;
    // A picture renders as a coloring page (line art on top); dropping the
    // template means a blank free-draw canvas. Brush strokes draw freely in
    // both — see [paintMode].
    paintMode.value = template == null ? PaintMode.draw : PaintMode.color;
  }

  /// Resets to a blank free-draw canvas: clears artwork + history, drops any
  /// template, and enters draw mode. Backs the Painting home's "Free Draw"
  /// entry, which then opens the canvas.
  void startFreeDraw() {
    _undoStack.clear();
    _redoStack.clear();
    actions.clear();
    currentStroke.value = null;
    selectedTemplate.value = null;
    clearSelection();
    _resetColoringBaseline();
    _setBackgroundImage(null);
    _editingTarget = null;
    paintMode.value = PaintMode.draw;
    // Free draw auto-snaps clear shapes (line / triangle / rect / circle) —
    // no toggle button; it just happens.
    autoShape.value = true;
    tool.value = DrawingTool.brush;
    resetZoom();
  }

  /// Re-opens a previously saved [drawing] to paint over: clears the canvas to a
  /// blank free-draw session, then loads the saved PNG as a backdrop the user
  /// draws on top of. The next save flattens backdrop + new strokes and, because
  /// [drawing] is remembered as the edit target, overwrites that gallery entry
  /// in place instead of creating a duplicate. Returns true once the image is
  /// loaded and active.
  Future<bool> repaintFromUrl(SavedDrawing drawing) async {
    try {
      final res = await http.get(Uri.parse(drawing.imageUrl));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('GET ${drawing.imageUrl} returned HTTP '
            '${res.statusCode}');
      }
      final codec = await ui.instantiateImageCodec(res.bodyBytes);
      final frame = await codec.getNextFrame();
      startFreeDraw(); // blank canvas first (also clears any prior backdrop)
      _setBackgroundImage(frame.image);
      // Editing over a picture, not a blank canvas: no shape-snapping (matches
      // the picture/template coloring tools). See [isFreeDraw].
      autoShape.value = false;
      // Set after startFreeDraw (which clears it) so saving edits this entry.
      _editingTarget = drawing;
      return true;
    } catch (e) {
      Get.snackbar(
        'Couldn\'t open drawing',
        '$e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
  }

  /// Loads a portal-managed coloring template from the Supabase `svg_assets`
  /// table (by [SvgAsset.publicUrl]) through the same parsing pipeline as
  /// uploads, then switches to it. Shows a brief progress snackbar and surfaces
  /// parse/network failures.
  /// Returns `true` once the picture is loaded and active so callers (the
  /// Painting home) can open the canvas only on success.
  Future<bool> selectTemplateFromUrl(SvgAsset asset) async {
    try {
      final page = await loadFromUrl(asset.resolvedUrl);
      final template = ColoringPageTemplate(
        page: page,
        name: asset.name,
        icon: Icons.image_outlined,
      );
      resetZoom();
      selectTemplate(template);
      return true;
    } catch (e, stack) {
      debugPrint('selectTemplateFromUrl: failed for "${asset.name}": $e');
      debugPrintStack(stackTrace: stack);
      Get.snackbar(
        'Template failed',
        'Could not load "${asset.name}": $e',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return false;
    }
  }

  /// Loads a portal **raster** picture (PNG/JPG) as a *color-over backdrop*:
  /// starts a blank free-draw canvas with the photo behind the strokes, so the
  /// child can draw and color on top of it. This is the separate "Color over a
  /// photo" mode — distinct from SVG coloring templates ([selectTemplateFromUrl]),
  /// which alone support clean vector region fills. Returns `true` once the image
  /// is loaded so the caller can open the canvas only on success.
  Future<bool> colorOverImageUrl(SvgAsset asset) async {
    try {
      final res = await http.get(Uri.parse(asset.resolvedUrl));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('GET ${asset.resolvedUrl} returned HTTP '
            '${res.statusCode}');
      }
      final codec = await ui.instantiateImageCodec(res.bodyBytes);
      final frame = await codec.getNextFrame();
      startFreeDraw(); // blank canvas; clears any prior template/backdrop
      _setBackgroundImage(frame.image);
      // Coloring over a photo: don't shape-snap the user's strokes.
      autoShape.value = false;
      return true;
    } catch (e) {
      Get.snackbar(
        'Couldn\'t open picture',
        '$e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
  }

  /// Opens the system file picker, loads the chosen SVG through the same
  /// pipeline as the bundled assets ([loadFromSvgString]), registers it as
  /// a template the picker remembers for the rest of the session, and
  /// switches to it.
  ///
  /// Surfaces failures via snackbar — picker cancellations are silent.
  /// Returns `true` once an uploaded SVG is parsed and active so the Painting
  /// home can open the canvas only on success (cancel/parse failure → false).
  Future<bool> uploadSvgTemplate() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['svg'],
        // We need the bytes either way; on iOS/Android paths are sandboxed
        // copies so reading by `path` works, but `withData` keeps the web
        // path consistent and avoids a second IO trip.
        withData: true,
      );
    } catch (e) {
      Get.snackbar(
        'Upload failed',
        'Could not open the file picker: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    if (result == null || result.files.isEmpty) return false; // user cancelled.

    final file = result.files.single;
    String svgContent;
    try {
      if (file.bytes != null) {
        svgContent = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        svgContent = await File(file.path!).readAsString();
      } else {
        Get.snackbar(
          'Upload failed',
          'The picker returned no readable data.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return false;
      }
    } catch (e) {
      Get.snackbar(
        'Upload failed',
        'Could not read "${file.name}": $e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }

    try {
      final page = await loadFromSvgString(
        svgContent,
        sourceLabel: file.name,
      );
      final displayName = file.name.replaceAll(
        RegExp(r'\.svg$', caseSensitive: false),
        '',
      );
      final template = ColoringPageTemplate(
        page: page,
        name: displayName.isEmpty ? 'Uploaded' : displayName,
        icon: Icons.upload_file,
      );
      // Mutating the global picker list is safe — the bottom sheet builds
      // off it lazily, so the new template appears next time the picker
      // opens. We auto-select it now so the user lands on their artwork
      // immediately.
      kTemplates.add(template);
      resetZoom();
      selectTemplate(template);
      Get.snackbar(
        'Loaded',
        '"${template.name}" is ready to color.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return true;
    } catch (e, stack) {
      debugPrint('uploadSvgTemplate: parse failed for "${file.name}": $e');
      debugPrintStack(stackTrace: stack);
      Get.snackbar(
        'Upload failed',
        'That file isn\'t a valid SVG we can color: $e',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return false;
    }
  }

  void _pushRecentColor(Color color) {
    final argb = color.toARGB32();
    recentColors.removeWhere((c) => c.toARGB32() == argb);
    recentColors.insert(0, color);
    if (recentColors.length > _recentColorsCap) {
      recentColors.removeRange(_recentColorsCap, recentColors.length);
    }
  }

  /// Opens the HSV color picker sheet and adopts the result on confirm.
  Future<void> openColorPicker(BuildContext context) async {
    final picked = await showColorPickerSheet(
      context: context,
      initial: selectedColor.value,
    );
    if (picked != null) selectColor(picked);
  }

  // ---------------------------------------------------------------------------
  // Undo / Redo / Clear
  // ---------------------------------------------------------------------------

  void _snapshotForUndo() {
    _undoStack.add(List<DrawAction>.from(actions));
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    clearSelection();
    _redoStack.add(List<DrawAction>.from(actions));
    actions.assignAll(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    clearSelection();
    _undoStack.add(List<DrawAction>.from(actions));
    actions.assignAll(_redoStack.removeLast());
  }

  void clearCanvas() {
    if (actions.isEmpty) return;
    clearSelection();
    _snapshotForUndo();
    _redoStack.clear();
    actions.clear();
  }

  /// True when the user has painted something (strokes or fills) on the current
  /// canvas — used to decide whether leaving should prompt to save.
  bool get hasArtwork => actions.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Renders the canvas to PNG bytes at [pixelRatio]. Returns null if the
  /// repaint boundary isn't mounted yet. `pixelRatio: 3` keeps exported lines
  /// crisp on high-DPI screens. Shared by save and share.
  Future<Uint8List?> renderCanvasPng({double pixelRatio = 3.0}) async {
    final boundary =
        repaintBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  /// Renders the canvas and tries to save it to the cloud via
  /// [SavedDrawingService]. Always returns the rendered [png] (when the canvas
  /// could be rasterized) so the result screen can display and share it even if
  /// the cloud save was skipped; [url] is the cloud image URL on success and
  /// [error] explains why a cloud save didn't happen (offline / signed out /
  /// failure).
  Future<({Uint8List? png, String? url, String? error})>
  saveCurrentDrawing() async {
    // Drop the selection highlight and let the canvas repaint before
    // rasterizing, so the highlight box never lands in the saved PNG.
    if (hasSelection) {
      clearSelection();
      await WidgetsBinding.instance.endOfFrame;
    }
    Uint8List? png;
    try {
      png = await renderCanvasPng();
    } catch (e) {
      return (png: null, url: null, error: 'Could not render the canvas: $e');
    }
    if (png == null) {
      return (png: null, url: null, error: 'Canvas is not ready yet.');
    }
    final target = _editingTarget;
    try {
      // Editing an existing drawing (Repaint): overwrite its gallery entry in
      // place, preserving its name/template, instead of inserting a duplicate.
      if (target != null) {
        final res = await SavedDrawingService.to.update(
          target,
          png: png,
          name: target.name,
          templateName: target.templateName,
        );
        // Track the new path/url so a second save keeps editing the same row.
        _editingTarget = SavedDrawing(
          id: target.id,
          name: target.name,
          imageUrl: res.url,
          filePath: res.path,
          templateName: target.templateName,
          createdAt: target.createdAt,
        );
        return (png: png, url: res.url, error: null);
      }
      final url = await SavedDrawingService.to.save(
        png: png,
        name: selectedTemplate.value?.name ?? 'Free draw',
        templateName: selectedTemplate.value?.name,
      );
      return (png: png, url: url, error: null);
    } catch (e) {
      return (png: png, url: null, error: e.toString());
    }
  }
}


