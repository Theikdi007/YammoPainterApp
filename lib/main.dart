import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/drawing_controller.dart';
import 'models/drawing_template.dart';
import 'widgets/painter.dart';
import 'widgets/templates.dart';
import 'widgets/tool_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initTemplates();
  runApp(const DrawPainterApp());
}

class DrawPainterApp extends StatelessWidget {
  const DrawPainterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    );
    return GetMaterialApp(
      title: 'Draw Painter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: DrawingScreen(),
    );
  }
}

class DrawingScreen extends StatelessWidget {
  DrawingScreen({super.key});

  /// Anchors the iOS popover for the system Share Sheet — passed to
  /// `Share.shareXFiles(sharePositionOrigin:)`. iPad requires it; iPhone
  /// ignores it but still rejects a zero-rect default in some iOS versions.
  final GlobalKey _shareButtonKey = GlobalKey();

  /// Predefined palette for the bottom color toolbar.
  static const List<Color> _palette = <Color>[
    Colors.black,
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.brown,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(DrawingController());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Draw Painter',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Primary actions stay visible: template, undo, redo, share.
          // Everything else moves into the overflow menu so the AppBar
          // doesn't overflow on phone-width screens.
          IconButton(
            tooltip: 'Pick a template',
            icon: const Icon(Icons.image_outlined),
            onPressed: () => _showTemplatePicker(context, controller),
          ),
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: controller.undo,
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
            onPressed: controller.redo,
          ),
          IconButton(
            key: _shareButtonKey,
            tooltip: 'Share or save',
            icon: const Icon(Icons.ios_share),
            onPressed: () {
              final box =
                  _shareButtonKey.currentContext?.findRenderObject()
                      as RenderBox?;
              Rect? origin;
              if (box != null && box.hasSize) {
                origin = box.localToGlobal(Offset.zero) & box.size;
              }
              controller.saveDrawing(sharePositionOrigin: origin);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final canvasWithActions = Stack(
              children: [
                Positioned.fill(child: _Canvas(controller: controller)),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(24),
                    elevation: 1,
                    child: CanvasActionsRow(controller: controller),
                  ),
                ),
              ],
            );

            if (orientation == Orientation.landscape) {
              // Collapse the three control strips into a single bottom row
              // so the canvas keeps its height on short-vertical screens.
              return Column(
                children: [
                  Expanded(child: canvasWithActions),
                  const Divider(height: 1),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      DrawingToolBar(controller: controller),
                      Expanded(
                        child: _ColorRow(
                          palette: _palette,
                          controller: controller,
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: _StrokeSlider(controller: controller),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Column(
              children: [
                Expanded(child: canvasWithActions),
                const Divider(height: 1),
                DrawingToolBar(controller: controller),
                _ColorRow(palette: _palette, controller: controller),
                _StrokeSlider(controller: controller),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Drawing surface. Uses a raw [Listener] (not [GestureDetector]) so we don't
/// claim the gesture arena — that lets the surrounding [InteractiveViewer]'s
/// scale recognizer win two-finger pinches even after we've started tracking
/// a one-finger draw. When a second pointer arrives we abort the in-flight
/// stroke so a pinch-zoom doesn't leave a stray scribble behind.
class _Canvas extends StatefulWidget {
  const _Canvas({required this.controller});

  final DrawingController controller;

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> {
  /// Pointers currently down on the canvas. Used to detect multi-touch.
  final Set<int> _activePointers = <int>{};

  /// The pointer we're treating as the drawing finger (the first one down
  /// while no others were active). Null if multi-touch or no touch.
  int? _drawingPointer;

  /// Where the drawing pointer first touched down. Held until the pointer
  /// either crosses the slop threshold (becomes a stroke) or lifts (becomes
  /// a tap).
  Offset? _downPosition;

  /// True once we've passed the slop and called [DrawingController.handlePanStart].
  bool _strokeStarted = false;

  bool _inBounds(Offset p, Size size) =>
      p.dx >= 0 && p.dy >= 0 && p.dx <= size.width && p.dy <= size.height;

  void _handlePointerDown(PointerDownEvent event, Size size) {
    _activePointers.add(event.pointer);

    if (_activePointers.length > 1) {
      // Second finger arrived — abandon any in-flight stroke and let
      // InteractiveViewer's pinch take over.
      if (_drawingPointer != null) {
        if (_strokeStarted) widget.controller.cancelStroke();
        _drawingPointer = null;
        _downPosition = null;
        _strokeStarted = false;
      }
      return;
    }

    if (!_inBounds(event.localPosition, size)) return;
    _drawingPointer = event.pointer;
    _downPosition = event.localPosition;
    _strokeStarted = false;
  }

  void _handlePointerMove(PointerMoveEvent event, Size size) {
    if (event.pointer != _drawingPointer || _activePointers.length > 1) return;
    final start = _downPosition;
    if (start == null) return;

    if (!_strokeStarted) {
      // Wait until the touch crosses the standard tap-slop threshold so a
      // shaky tap doesn't leave a tiny stroke behind (and so taps can still
      // route to bucket fill / eyedropper).
      if ((event.localPosition - start).distance < kTouchSlop) return;
      widget.controller.handlePanStart(
        DragStartDetails(
          globalPosition: event.position - event.delta,
          localPosition: start,
        ),
        size,
      );
      _strokeStarted = true;
    }

    if (!_inBounds(event.localPosition, size)) return;
    widget.controller.handlePanUpdate(
      DragUpdateDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        delta: event.delta,
      ),
      size,
    );
  }

  void _handlePointerEnd(
    PointerEvent event,
    Size size, {
    required bool cancelled,
  }) {
    _activePointers.remove(event.pointer);
    if (event.pointer != _drawingPointer) return;
    final start = _downPosition;
    if (cancelled) {
      if (_strokeStarted) widget.controller.cancelStroke();
    } else if (_strokeStarted) {
      widget.controller.handlePanEnd(DragEndDetails());
    } else if (start != null && _inBounds(start, size)) {
      widget.controller.handleTap(start, size);
    }
    _drawingPointer = null;
    _downPosition = null;
    _strokeStarted = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        // Pan/zoom is automatic via two-finger pinch (handled by
        // InteractiveViewer's scale gesture). Single-finger drags are
        // forwarded by the Listener below and become drawing strokes.
        return InteractiveViewer(
          transformationController: widget.controller.transformationController,
          panEnabled: false,
          scaleEnabled: true,
          minScale: 1.0,
          maxScale: 4.0,
          child: RepaintBoundary(
            key: widget.controller.repaintBoundaryKey,
            child: ClipRect(
              child: Container(
                color: Colors.white,
                width: size.width,
                height: size.height,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _handlePointerDown(e, size),
                  onPointerMove: (e) => _handlePointerMove(e, size),
                  onPointerUp: (e) =>
                      _handlePointerEnd(e, size, cancelled: false),
                  onPointerCancel: (e) =>
                      _handlePointerEnd(e, size, cancelled: true),
                  child: Obx(
                    // .toList() forces a fresh List instance so
                    // CustomPaint.shouldRepaint observes inequality.
                    () => CustomPaint(
                      painter: Painter(
                        actions: widget.controller.actions.toList(),
                        currentStroke: widget.controller.currentStroke.value,
                        template: widget.controller.selectedTemplate.value,
                      ),
                      size: size,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Horizontally-scrolling color row: recent colors first, then preset
/// swatches, then a "+" tile that opens the HSV picker. The active swatch
/// gets a thicker outline.
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.palette, required this.controller});

  final List<Color> palette;
  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Obx(() {
          final selected = controller.selectedColor.value;
          final recents = controller.recentColors;
          return Row(
            children: [
              for (final color in recents)
                _Swatch(
                  color: color,
                  selected: color.toARGB32() == selected.toARGB32(),
                  onTap: () => controller.selectColor(color),
                ),
              if (recents.isNotEmpty) const _RowDivider(),
              for (final color in palette)
                _Swatch(
                  color: color,
                  selected: color.toARGB32() == selected.toARGB32(),
                  onTap: () => controller.selectColor(color),
                ),
              const _RowDivider(),
              _PickerPlusButton(
                onTap: () => controller.openColorPicker(context),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 1,
        height: 28,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _PickerPlusButton extends StatelessWidget {
  const _PickerPlusButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outline, width: 1.5),
            color: scheme.surface,
          ),
          child: Icon(Icons.add, color: scheme.primary),
        ),
      ),
    );
  }
}

class _StrokeSlider extends StatelessWidget {
  const _StrokeSlider({required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Obx(
        () => Row(
          children: [
            Text('Stroke', style: Theme.of(context).textTheme.bodySmall),
            Expanded(
              child: Slider(
                min: 1.0,
                max: 40.0,
                divisions: 39,
                value: controller.strokeWidth.value,
                label: controller.strokeWidth.value.toStringAsFixed(1),
                onChanged: controller.setStrokeWidth,
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                controller.strokeWidth.value.toStringAsFixed(1),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showTemplatePicker(BuildContext context, DrawingController controller) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pick a template',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _TemplateTile(
                      label: 'Free',
                      icon: Icons.crop_free,
                      onTap: () {
                        controller.selectTemplate(null);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                    _TemplateTile(
                      label: 'Upload SVG',
                      icon: Icons.upload_file,
                      onTap: () {
                        // Close the sheet first so the file picker isn't
                        // stacked on top of it; then run the import.
                        Navigator.of(sheetContext).pop();
                        controller.uploadSvgTemplate();
                      },
                    ),
                    for (final template in kTemplates)
                      _TemplateTile.fromTemplate(
                        template: template,
                        onTap: () {
                          controller.selectTemplate(template);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.template,
  });

  factory _TemplateTile.fromTemplate({
    required DrawingTemplate template,
    required VoidCallback onTap,
  }) {
    return _TemplateTile(
      label: template.name,
      icon: template.icon,
      onTap: onTap,
      template: template,
    );
  }

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final DrawingTemplate? template;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: template == null
                  ? Center(child: Icon(icon, size: 36, color: Colors.black54))
                  : CustomPaint(
                      painter: _TemplateThumbnailPainter(template: template!),
                      size: Size.infinite,
                    ),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TemplateThumbnailPainter extends CustomPainter {
  _TemplateThumbnailPainter({required this.template});

  final DrawingTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    template.paintPreview(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _TemplateThumbnailPainter oldDelegate) =>
      oldDelegate.template != template;
}
