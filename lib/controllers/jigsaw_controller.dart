import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../jigsaw/jigsaw_path_builder.dart';
import '../jigsaw/sample_images.dart';
import '../models/puzzle_piece.dart';
import '../models/svg_asset.dart';

/// The four difficulty presets, keyed by approximate pieces-per-side.
class JigsawLevel {
  const JigsawLevel(this.name, this.perSide);
  final String name;
  final int perSide;
}

const List<JigsawLevel> kJigsawLevels = [
  JigsawLevel('Easy', 3),
  JigsawLevel('Medium', 4),
  JigsawLevel('Hard', 5),
  JigsawLevel('Expert', 6),
];

/// Selectable board backgrounds (the felt/wood-table feel under the puzzle).
class JigsawBackground {
  const JigsawBackground(this.name, this.colors);
  final String name;
  final List<Color> colors;
}

const List<JigsawBackground> kBackgrounds = [
  JigsawBackground('Light', [Color(0xFFF4F4F8), Color(0xFFE3E4EC)]),
  JigsawBackground('Slate', [Color(0xFF2C313C), Color(0xFF12151C)]),
  JigsawBackground('Wood', [Color(0xFFC79A6F), Color(0xFF7F5539)]),
  JigsawBackground('Felt', [Color(0xFF1E8A56), Color(0xFF0C4F31)]),
  JigsawBackground('Ocean', [Color(0xFF2C5364), Color(0xFF0F2027)]),
];

/// Owns all mutable state for the jigsaw puzzle: source image, the pieces,
/// the zoom transform, board view options, the clock and the win condition.
class JigsawController extends GetxController {
  /// Transparent breathing room baked around every piece so its drop shadow
  /// and lift scale aren't clipped by the widget bounds.
  static const double pad = 16;

  final Rx<ui.Image?> image = Rx<ui.Image?>(null);
  final RxInt selectedSample = (-1).obs;
  final RxBool loadingImage = false.obs;

  final RxList<PuzzlePiece> pieces = <PuzzlePiece>[].obs;

  /// False until a puzzle has been generated for the current play screen.
  final RxBool ready = false.obs;

  final RxInt level = kJigsawLevels[1].perSide.obs;
  final RxInt moves = 0.obs;
  final RxInt placedCount = 0.obs;
  final RxInt elapsed = 0.obs;
  final RxBool solved = false.obs;

  // Board view options.
  final RxBool hintOn = false.obs; // show the picture ghost as a guide
  final RxBool homeMarkerOn = true.obs; // green marker at a dragged piece's home
  final RxBool edgesOnly = false.obs; // tray shows only border pieces
  final RxInt backgroundIndex = 0.obs;

  // Live drag state for the board's home-marker.
  final Rx<PuzzlePiece?> draggingPiece = Rx<PuzzlePiece?>(null);
  final RxBool overHome = false.obs;

  /// Zoom / pan for the board (pinch + the +/- buttons).
  final TransformationController transformationController =
      TransformationController();

  Size boardArea = Size.zero; // the InteractiveViewer viewport
  Size boardSize = Size.zero; // the assembled-puzzle rect
  int cols = 0;
  int rows = 0;
  double snapThreshold = 28;

  Timer? _timer;
  int _seed = 0;

  int get totalPieces => pieces.length;
  int get unplacedCount => pieces.where((p) => !p.placed.value).length;
  double get currentScale => transformationController.value.getMaxScaleOnAxis();

  /// Pieces shown in the tray: unplaced, optionally filtered to edges. The
  /// edge filter is ignored once no unplaced edge pieces remain, so the tray
  /// never hides the last interior pieces.
  List<PuzzlePiece> get trayPieces {
    final unplaced = pieces.where((p) => !p.placed.value).toList();
    if (edgesOnly.value && unplaced.any((p) => p.isEdge)) {
      return unplaced.where((p) => p.isEdge).toList();
    }
    return unplaced;
  }

  @override
  void onClose() {
    _timer?.cancel();
    image.value?.dispose();
    transformationController.dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // Image source
  // ---------------------------------------------------------------------------

  void setLevel(int perSide) => level.value = perSide;

  /// Loads a portal photo as the source image. Returns true when a new image
  /// was set (so the caller can open the play screen), false when it was locked
  /// or failed to load.
  Future<bool> useAsset(SvgAsset asset) async {
    if (asset.isLocked) {
      Get.snackbar(
        'Locked',
        'This photo isn\'t available yet.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return false;
    }
    loadingImage.value = true;
    try {
      _replaceImage(await loadImageFromUrl(asset.resolvedUrl));
      selectedSample.value = -1;
      return true;
    } catch (e) {
      Get.snackbar(
        'Could not load image',
        '$e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    } finally {
      loadingImage.value = false;
    }
  }

  void _replaceImage(ui.Image img) {
    image.value?.dispose();
    image.value = img;
  }

  /// Called by the setup screen just before pushing the play screen, so the
  /// play screen regenerates with the freshly chosen image / difficulty.
  void prepareNewGame() {
    _stopTimer();
    ready.value = false;
    solved.value = false;
    pieces.clear();
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  /// Builds a fresh puzzle sized to fit [area] (the board viewport).
  void generate(Size area) {
    final img = image.value;
    if (img == null) return;
    boardArea = area;

    final aspect = img.width / img.height;
    final maxW = area.width - 24;
    final maxH = area.height - 24;
    var w = maxW;
    var h = w / aspect;
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }
    boardSize = Size(w, h);

    final sa = math.sqrt(aspect);
    cols = math.max(2, (level.value * sa).round());
    rows = math.max(2, (level.value / sa).round());
    snapThreshold = math.max(
      30.0,
      0.6 * math.min(boardSize.width / cols, boardSize.height / rows),
    );

    final rng = math.Random(_seed++ * 911 + cols * 31 + rows);
    final specs = buildPieces(
      size: boardSize,
      rows: rows,
      cols: cols,
      rng: rng,
    );

    final built = <PuzzlePiece>[];
    var id = 0;
    for (final spec in specs) {
      final local =
          spec.path.shift(-spec.bounds.topLeft + const Offset(pad, pad));
      built.add(
        PuzzlePiece(
          id: id++,
          row: spec.row,
          col: spec.col,
          localPath: local,
          size: Size(spec.bounds.width + pad * 2, spec.bounds.height + pad * 2),
          imageOffset: Offset(pad - spec.bounds.left, pad - spec.bounds.top),
          boardPosition: spec.bounds.topLeft - const Offset(pad, pad),
          boardCenter: spec.bounds.center,
          isEdge: spec.row == 0 ||
              spec.col == 0 ||
              spec.row == rows - 1 ||
              spec.col == cols - 1,
        ),
      );
    }
    built.shuffle(rng); // randomize tray order

    pieces.assignAll(built);
    transformationController.value = Matrix4.identity();
    moves.value = 0;
    placedCount.value = 0;
    elapsed.value = 0;
    solved.value = false;
    draggingPiece.value = null;
    overHome.value = false;
    ready.value = true;
    _startTimer();
  }

  // ---------------------------------------------------------------------------
  // Drag & drop
  // ---------------------------------------------------------------------------

  void startDrag(PuzzlePiece p) {
    draggingPiece.value = p;
    overHome.value = false;
    HapticFeedback.selectionClick(); // a light tick on pick-up
  }

  void endDrag() {
    draggingPiece.value = null;
    overHome.value = false;
  }

  /// Updates whether the dragged piece is hovering its home, ticking once on
  /// the moment it enters the home zone so the user can feel the right spot.
  void setOverHome(bool value) {
    if (value && !overHome.value) HapticFeedback.selectionClick();
    overHome.value = value;
  }

  bool isNearHome(PuzzlePiece p, Offset boardPoint) =>
      (boardPoint - p.boardCenter).distance <= snapThreshold;

  /// Locks [p] into its home. Fires a short haptic tick; a heavier one on the
  /// final piece.
  void place(PuzzlePiece p) {
    if (p.placed.value) return;
    p.placed.value = true;
    placedCount.value++;
    moves.value++;
    HapticFeedback.mediumImpact();
    // Once the frame is done, the edge filter would only hide the remaining
    // interior pieces — drop it so they reappear.
    if (edgesOnly.value && !pieces.any((q) => !q.placed.value && q.isEdge)) {
      edgesOnly.value = false;
    }
    pieces.refresh();
    _checkSolved();
  }

  // ---------------------------------------------------------------------------
  // View options
  // ---------------------------------------------------------------------------

  void toggleHint() => hintOn.toggle();
  void toggleHomeMarker() => homeMarkerOn.toggle();
  void toggleEdges() => edgesOnly.toggle();
  void setBackground(int i) => backgroundIndex.value = i;

  void zoomBy(double factor) {
    if (boardArea.isEmpty) return;
    final current = currentScale;
    final target = (current * factor).clamp(1.0, 3.5);
    final f = target / current;
    if ((f - 1).abs() < 0.001) return;
    final c = Offset(boardArea.width / 2, boardArea.height / 2);
    // Zoom about the viewport centre while preserving the current pan: the
    // delta is pre-multiplied (it acts in viewport space).
    final delta = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    transformationController.value =
        delta.multiplied(transformationController.value);
  }

  void resetZoom() => transformationController.value = Matrix4.identity();

  /// Stops the clock without resetting it — called when the play screen is left.
  void pause() => _stopTimer();

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Returns every piece to the tray and restarts the clock (same image/cut).
  void restart() {
    for (final p in pieces) {
      p.placed.value = false;
    }
    pieces.shuffle(math.Random(_seed++ * 733 + 17));
    pieces.refresh();
    resetZoom();
    moves.value = 0;
    placedCount.value = 0;
    elapsed.value = 0;
    solved.value = false;
    draggingPiece.value = null;
    overHome.value = false;
    _startTimer();
  }

  void solveAll() {
    for (final p in pieces) {
      p.placed.value = true;
    }
    placedCount.value = pieces.length;
    pieces.refresh();
    _checkSolved();
  }

  void _checkSolved() {
    if (placedCount.value >= pieces.length && pieces.isNotEmpty) {
      solved.value = true;
      _stopTimer();
      _celebrateBuzz();
    }
  }

  /// A celebratory triple-buzz when the whole puzzle is solved.
  Future<void> _celebrateBuzz() async {
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    HapticFeedback.heavyImpact();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!solved.value) elapsed.value++;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String get elapsedLabel {
    final s = elapsed.value;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}
