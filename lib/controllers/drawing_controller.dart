import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../coloring/coloring_page_template.dart';
import '../coloring/parsing/coloring_page_loader.dart';
import '../models/drawing_template.dart';
import '../models/drawing_tool.dart';
import '../models/stroke.dart';
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

  /// Most-recently used custom colors, MRU-ordered, capped at 8.
  final RxList<Color> recentColors = <Color>[].obs;
  static const int _recentColorsCap = 8;

  /// Currently selected coloring-book template. `null` means free-draw mode
  /// (paint anywhere on the canvas).
  final Rx<DrawingTemplate?> selectedTemplate = Rx<DrawingTemplate?>(null);

  /// Wraps the canvas so we can rasterize it for [saveDrawing] (and for the
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
    super.onClose();
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
    );
  }

  void handlePanStart(DragStartDetails details, Size canvasSize) {
    if (!_toolIsPan) return;

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
    currentStroke.value = _emitCurrentStroke();
  }

  void handlePanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (!_toolIsPan || _currentStrokePoints.isEmpty) return;
    final template = selectedTemplate.value;
    final fit = template?.fitTransform(canvasSize);
    final p = (fit == null)
        ? details.localPosition
        : template!.canvasToPicture(details.localPosition, canvasSize);
    _currentStrokePoints.add(p);
    // Re-emit a fresh Stroke so Rx fires and the painter sees the new
    // point. Re-using the same object wouldn't trigger reactivity.
    currentStroke.value = _emitCurrentStroke();
  }

  void handlePanEnd(DragEndDetails details) {
    if (!_toolIsPan || _currentStrokePoints.isEmpty) return;
    actions.add(_emitCurrentStroke());
    _currentStrokePoints.clear();
    currentStroke.value = null;
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

  /// Tap-driven tools. Pan tools (`brush`/`eraser`) ignore single taps —
  /// gestures arrive as pan events instead.
  Future<void> handleTap(Offset localPosition, Size canvasSize) async {
    switch (tool.value) {
      case DrawingTool.bucket:
        _bucketFillAt(localPosition, canvasSize);
      case DrawingTool.eyedropper:
        await _eyedropAt(localPosition, canvasSize);
      case DrawingTool.brush:
      case DrawingTool.eraser:
        return;
    }
  }

  void _bucketFillAt(Offset localPosition, Size canvasSize) {
    final template = selectedTemplate.value;
    if (template == null) return;
    final regions = template.buildRegions(canvasSize);
    if (regions.isEmpty) return;

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
    if (hit == null) return;

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
  }

  /// Opens the system file picker, loads the chosen SVG through the same
  /// pipeline as the bundled assets ([loadFromSvgString]), registers it as
  /// a template the picker remembers for the rest of the session, and
  /// switches to it.
  ///
  /// Surfaces failures via snackbar — picker cancellations are silent.
  Future<void> uploadSvgTemplate() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
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
      return;
    }
    if (result == null || result.files.isEmpty) return; // user cancelled.

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
        return;
      }
    } catch (e) {
      Get.snackbar(
        'Upload failed',
        'Could not read "${file.name}": $e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
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
      selectTemplate(template);
      Get.snackbar(
        'Loaded',
        '"${template.name}" is ready to color.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    } catch (e, stack) {
      debugPrint('uploadSvgTemplate: parse failed for "${file.name}": $e');
      debugPrintStack(stackTrace: stack);
      Get.snackbar(
        'Upload failed',
        'That file isn\'t a valid SVG we can color: $e',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
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
    _redoStack.add(List<DrawAction>.from(actions));
    actions.assignAll(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List<DrawAction>.from(actions));
    actions.assignAll(_redoStack.removeLast());
  }

  void clearCanvas() {
    if (actions.isEmpty) return;
    _snapshotForUndo();
    _redoStack.clear();
    actions.clear();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Renders the canvas as a PNG and hands it to the system Share Sheet.
  ///
  /// On iOS the user can pick **Save Image** (the OS handles the Photos
  /// permission prompt natively, with no `permission_handler` plumbing), or
  /// **Save to Files**, **Messages**, **Mail**, etc. On Android the same
  /// share intent surfaces equivalent destinations.
  ///
  /// [sharePositionOrigin] is the on-screen rect the iOS popover anchors
  /// to — required on iPad (and on recent iOS) or `Share.shareXFiles`
  /// throws *"argument must be set, {{0,0},{0,0}} must be non-zero"*.
  /// Pass the share button's global rect; `null` falls back to the
  /// top-right corner of the window.
  ///
  /// Errors are surfaced via snackbar; user dismissing the share sheet is a
  /// silent no-op (Share API doesn't return an error for that).
  Future<void> saveDrawing({Rect? sharePositionOrigin}) async {
    try {
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        Get.snackbar(
          'Save failed',
          'Canvas is not ready yet — try again in a moment.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      // pixelRatio: 3 keeps exported lines crisp on high-DPI screens.
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        Get.snackbar(
          'Save failed',
          'Could not encode the drawing.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();

      // Write to a temp file; share_plus uses real file paths so iOS UTI
      // detection picks `public.png` and the share sheet offers Save Image.
      final tmp = await getTemporaryDirectory();
      final filename = 'draw_painter_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tmp.path}/$filename');
      await file.writeAsBytes(pngBytes, flush: true);

      // Fallback: a tiny rect near the top-right of the screen. iOS just
      // needs *some* non-zero rect within the window's coordinate space;
      // for non-iPad devices the popover rect is ignored anyway.
      final origin = sharePositionOrigin ??
          (Rect.fromLTWH(
            ui.PlatformDispatcher.instance.implicitView!.physicalSize.width /
                    ui.PlatformDispatcher.instance.implicitView!
                        .devicePixelRatio -
                40,
            40,
            32,
            32,
          ));

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: filename)],
        subject: 'Draw Painter',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      Get.snackbar(
        'Save failed',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}


