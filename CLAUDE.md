# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter app `yammopatinerapp` — "Draw Painter," a freehand drawing app with a coloring-book template mode. Targets all six Flutter platforms (`android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`). Dart SDK constraint: `^3.11.4`. Lints: `package:flutter_lints/flutter.yaml` (overrides go in `analysis_options.yaml` under `linter.rules:`).

`draw_painter_ai_prompt.md` describes a planned AI integration layer (`lib/config/`, `AiClient` abstraction, image→text/image→image flows). It is **not yet implemented** — treat it as design intent, not current architecture.

## Commands

```bash
flutter pub get                           # install / sync dependencies
flutter run                               # run on the default device
flutter run -d chrome                     # run on a specific device (chrome/macos/ios/...)
flutter analyze                           # static analysis
flutter test                              # run all tests
flutter test test/widget_test.dart        # run a single test file
flutter test --name "Draw Painter"        # run tests matching a name
flutter build apk | ios | macos | web | windows | linux
```

## Architecture

State management is **GetX** (`get: ^4.6.5`) — the app uses `GetMaterialApp`, `Get.put` for DI, `Rx`/`Obx` for reactivity, and `Get.snackbar` for user feedback. Don't introduce a second state-management library alongside it.

Layout:

- `lib/main.dart` — `DrawPainterApp` (root), `DrawingScreen` (Scaffold + AppBar actions), `_Canvas`, `_ColorPalette`, `_StrokeSlider`, and the template-picker bottom sheet.
- `lib/controllers/drawing_controller.dart` — `DrawingController extends GetxController`. Single owner of mutable state: `allPoints`, `undoStack`, `redoStack`, `selectedColor`, `strokeWidth`, `selectedTemplate`, and the `repaintBoundaryKey` used to rasterize the canvas. Also handles `saveDrawing()` (permissions → `RenderRepaintBoundary.toImage` → PNG → `image_gallery_saver`).
- `lib/models/drawing_point.dart` — `DrawingPoint { Offset point; Paint paint; }`.
- `lib/models/drawing_template.dart` — abstract `DrawingTemplate` with `buildFillPath(size)`, `buildRegions(size)`, `paintOutline(canvas, size)`.
- `lib/widgets/painter.dart` — `Painter extends CustomPainter`. Walks `points` stroke-by-stroke and applies per-stroke clipping when a template is active.
- `lib/widgets/templates.dart` — `kTemplates` list (Heart, Star, Circle, Flower, Butterfly) and the shared outline `Paint`.

## Invariants worth knowing before editing

These aren't obvious from a quick read but the app breaks subtly if you violate them:

- **`null` entries in `allPoints` are stroke separators** (emitted on `onPanEnd`). Without them, `Painter` would draw a line between the end of one stroke and the start of the next. Anything that mutates `allPoints` must preserve this convention.
- **`DrawingPoint.paint` is captured at the moment the point is added.** Changing `selectedColor` or `strokeWidth` later must NOT retroactively re-style committed strokes. If you refactor stroke storage, keep this property.
- **Undo/redo snapshots whole strokes, not points.** `handlePanStart` pushes `allPoints` onto `undoStack` *before* mutating; `handlePanUpdate` does not. Adding new mutation paths means deciding where the snapshot belongs.
- **Per-stroke region clipping.** When a template is active, each stroke is clipped to the *single region whose path contains the stroke's first point* (see `lib/widgets/painter.dart`). This is what prevents paint from bleeding between, e.g., flower petals or butterfly wings. The order regions are returned from `buildRegions` matters — the first match wins, so list overlapping inner regions (flower center, butterfly body) before the outer ones they overlap with.
- **Canvas hit-test bounds check.** `_Canvas` in `lib/main.dart` wraps the gesture detector in a `LayoutBuilder` and drops pan events whose `localPosition` falls outside the canvas. Without this, once Flutter claims the pan gesture it keeps delivering updates when the finger drifts onto the toolbar/slider, producing stray strokes. Don't remove the `inBounds` guard.
- **`Obx(() => CustomPaint(painter: Painter(points: controller.allPoints.toList(), ...)))`** — the `.toList()` is load-bearing. `CustomPaint.shouldRepaint` compares list identity; without a fresh `List` instance, repaints are skipped.
- **`saveDrawing` uses `pixelRatio: 3.0`** when rasterizing the `RepaintBoundary` so exported PNGs stay crisp on high-DPI screens. Lower it only with intent.
- **Permission surface differs by platform** in `saveDrawing`: iOS requests `Permission.photos`, everything else requests `Permission.storage`. `image_gallery_saver` works on mobile; desktop/web saves are not currently wired up.
