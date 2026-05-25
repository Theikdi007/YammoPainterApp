## AI Prompt: Generate a Flutter Draw Painter App with GetX and Detailed UI/UX

**Goal:** Generate a complete Flutter application for a "Draw Painter" app, implementing freehand drawing, color and stroke width selection, undo/redo functionality, clear canvas, and saving drawings to the device gallery. The application must adhere to the provided UI/UX design specifications and utilize GetX for state management.

**Technology Stack:**
*   Flutter
*   GetX (State Management, Dependency Injection, Route Management, Snackbars)
*   `CustomPainter` for drawing
*   `RepaintBoundary` for performance optimization

**Core Features to Implement:**
1.  **Freehand Drawing:** Users can draw on a canvas using touch input.
2.  **Color Selection:** A horizontal scrollable palette of predefined colors.
3.  **Stroke Width Adjustment:** A slider to control the thickness of the drawing line.
4.  **Undo/Redo Functionality:** Buttons to revert and reapply drawing strokes.
5.  **Clear Canvas:** A button to erase all drawings.
6.  **Save Drawing:** Export the current canvas content as a PNG image to the device gallery, including necessary permission handling.

**Architecture:**
*   **`main.dart`:** Application entry point and `GetMaterialApp` setup.
*   **`DrawingPoint` (Model):** A simple data class (`lib/models/drawing_point.dart`) to represent each point drawn, containing `Offset point` and `Paint paint` properties.
*   **`Painter` (CustomPainter):** A custom painter class (`lib/widgets/painter.dart`) responsible for rendering the `List<DrawingPoint?>` on the `Canvas`.
*   **`DrawingController` (GetX Controller):** (`lib/controllers/drawing_controller.dart`) Manages all application state related to drawing:
    *   `RxList<DrawingPoint?> allPoints`: Stores all drawn points, with `null` acting as a separator between distinct strokes.
    *   `RxList<List<DrawingPoint?>> undoStack`: Stores previous states of `allPoints` for undo operations.
    *   `RxList<List<DrawingPoint?>> redoStack`: Stores states for redo operations.
    *   `Rx<Color> selectedColor`: Current drawing color.
    *   `Rx<double> strokeWidth`: Current stroke thickness.
    *   `GlobalKey repaintBoundaryKey`: Key for `RepaintBoundary` to capture the canvas as an image.
    *   Methods: `handlePanStart`, `handlePanUpdate`, `handlePanEnd` for gesture detection and updating `allPoints`. `selectColor`, `setStrokeWidth`, `undo`, `redo`, `clearCanvas`, `saveDrawing`.
*   **`DrawingScreen` (Flutter Widget):** (`lib/main.dart`) The main UI widget that uses `Get.put(DrawingController())` and `Obx` widgets to react to state changes. It contains the `RepaintBoundary` wrapped `CustomPaint` and the control widgets.

**UI/UX Design Specifications:**

**Design Principles:**
*   **Simplicity & Clarity:** Clean, uncluttered interface.
*   **Intuitiveness:** Natural and predictable interactions.
*   **Responsiveness:** Adapts to different screen sizes/orientations.
*   **Performance:** Smooth animations and quick feedback.
*   **Aesthetics:** Modern, clean visual style.

**Screen Layout:**
*   **Top App Bar:**
    *   **Title:** "Draw Painter" (centered or left-aligned).
    *   **Action Buttons (Right-aligned):** `IconButton`s for Undo (`Icons.undo`), Redo (`Icons.redo`), Clear (`Icons.clear`), Save (`Icons.save`).
*   **Canvas Area (Main Content):**
    *   Occupies the majority of the screen, below the app bar.
    *   Wrapped in a `RepaintBoundary` widget using `drawingController.repaintBoundaryKey`.
    *   Contains a `GestureDetector` for pan events, which wraps a `CustomPaint` widget.
    *   Background color: `Colors.white`.
*   **Bottom Toolbar (Color Palette):**
    *   A `SingleChildScrollView` with `Axis.horizontal` containing a `Row` of color swatches.
    *   Located directly below the canvas.
*   **Bottom Slider (Stroke Width):**
    *   A `Slider` widget for adjusting stroke thickness.
    *   Located below the color palette.

**Component Details:**
*   **Color Swatches:** Circular `GestureDetector`s (e.g., `Container` with `BoxShape.circle`) displaying different colors. When selected, the swatch should have a `Colors.blueAccent` border with `width: 2`.
*   **Stroke Width Slider:** Range from `1.0` to `20.0`, with `divisions: 19`. Display the current value as a `label`.
*   **Snackbars:** Use `Get.snackbar` for user feedback (e.g., "Drawing saved to gallery!", "Permission Denied").

**Design System:**
*   **Typography:** Default Flutter font. App Bar Title: `headlineSmall`. Snackbar Text: `bodyMedium`. Stroke Width Label: `bodySmall`.
*   **Color Palette:**
    *   Primary: `Colors.blue` (for App Bar, selected states).
    *   Accent: `Colors.blueAccent` (for selected color swatch border).
    *   Canvas Background: `Colors.white`.
    *   Drawing Colors: `Colors.black`, `Colors.red`, `Colors.green`, `Colors.blue`, `Colors.yellow`, `Colors.purple`, `Colors.orange`, `Colors.brown`.
    *   Icon Colors: `Colors.white` (on primary app bar).
*   **Iconography:** Material Design Icons (`Icons.undo`, `Icons.redo`, `Icons.clear`, `Icons.save`).

**Dependencies (to be added in `pubspec.yaml`):**
```yaml
dependencies:
  flutter:
    sdk: flutter
  get: ^4.6.5
  image_gallery_saver: ^2.0.3
  path_provider: ^2.0.11
  permission_handler: ^10.2.0
```

**Implementation Details & Constraints:**
*   Ensure `GetMaterialApp` is used as the root widget.
*   The `DrawingController` should be initialized using `Get.put()`.
*   Use `Obx` widgets to reactively update the UI based on `DrawingController`'s `Rx` variables.
*   For `saveDrawing` function, ensure proper permission handling for storage using `permission_handler` and saving to gallery using `image_gallery_saver`.
*   The `Painter` class's `paint` method should correctly draw lines between consecutive `DrawingPoint`s. A `null` in `allPoints` signifies the end of a stroke.
*   The `undo` and `redo` logic should correctly manage `undoStack` and `redoStack` to store and restore `allPoints` states.
*   The `handlePanEnd` method should add a `null` to `allPoints` to separate distinct drawing strokes.

**Output:** Provide the complete, runnable Flutter project code, organized into the specified file structure (`lib/main.dart`, `lib/models/drawing_point.dart`, `lib/widgets/painter.dart`, `lib/controllers/drawing_controller.dart`). Include the `pubspec.yaml` content. The code should be well-commented and follow Flutter best practices.