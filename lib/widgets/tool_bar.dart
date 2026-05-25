import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/drawing_controller.dart';
import '../models/drawing_tool.dart';

/// Compact tool selector: brush / eraser / bucket / eyedropper, plus a
/// brush-style popup that's only enabled while the brush tool is active.
class DrawingToolBar extends StatelessWidget {
  const DrawingToolBar({super.key, required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Obx(
            () => _ToolButton(
              icon: Icons.brush,
              label: 'Brush',
              selected: controller.tool.value == DrawingTool.brush,
              onPressed: () => controller.selectTool(DrawingTool.brush),
            ),
          ),
          Obx(
            () => _BrushStylePicker(
              enabled: controller.tool.value == DrawingTool.brush,
              current: controller.brushStyle.value,
              onSelected: controller.selectBrushStyle,
            ),
          ),
          const SizedBox(width: 8),
          Obx(
            () => _ToolButton(
              icon: Icons.cleaning_services_outlined,
              label: 'Eraser',
              selected: controller.tool.value == DrawingTool.eraser,
              onPressed: () => controller.selectTool(DrawingTool.eraser),
            ),
          ),
          Obx(
            () => _ToolButton(
              icon: Icons.format_color_fill,
              label: 'Fill',
              selected: controller.tool.value == DrawingTool.bucket,
              onPressed: () => controller.selectTool(DrawingTool.bucket),
            ),
          ),
          Obx(
            () => _ToolButton(
              icon: Icons.colorize,
              label: 'Pick',
              selected: controller.tool.value == DrawingTool.eyedropper,
              onPressed: () => controller.selectTool(DrawingTool.eyedropper),
            ),
          ),
        ],
      ),
    );
  }
}

/// Right-aligned strip that sits above the toolbar divider. Holds Reset zoom
/// (always shown, disabled until the canvas is zoomed) and Clear.
class CanvasActionsRow extends StatelessWidget {
  const CanvasActionsRow({super.key, required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ValueListenableBuilder<Matrix4>(
            valueListenable: controller.transformationController,
            builder: (context, matrix, _) {
              final isZoomed = !matrix.isIdentity();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: isZoomed ? controller.resetZoom : null,
                  icon: const Icon(Icons.fit_screen, size: 18),
                  label: const Text('Reset zoom'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              );
            },
          ),
          OutlinedButton.icon(
            onPressed: controller.clearCanvas,
            icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
            label: Text('Clear', style: TextStyle(color: scheme.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    final bg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHigh;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrushStylePicker extends StatelessWidget {
  const _BrushStylePicker({
    required this.enabled,
    required this.current,
    required this.onSelected,
  });

  final bool enabled;
  final BrushStyle current;
  final ValueChanged<BrushStyle> onSelected;

  IconData _iconFor(BrushStyle s) {
    switch (s) {
      case BrushStyle.round:
        return Icons.circle;
      case BrushStyle.soft:
        return Icons.blur_on;
      case BrushStyle.marker:
        return Icons.edit;
      case BrushStyle.pencil:
        return Icons.create;
    }
  }

  String _labelFor(BrushStyle s) {
    switch (s) {
      case BrushStyle.round:
        return 'Round';
      case BrushStyle.soft:
        return 'Soft';
      case BrushStyle.marker:
        return 'Marker';
      case BrushStyle.pencil:
        return 'Pencil';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: PopupMenuButton<BrushStyle>(
        enabled: enabled,
        tooltip: 'Brush style',
        initialValue: current,
        icon: Icon(_iconFor(current), size: 20),
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final s in BrushStyle.values)
            PopupMenuItem<BrushStyle>(
              value: s,
              child: Row(
                children: [
                  Icon(_iconFor(s), size: 18),
                  const SizedBox(width: 8),
                  Text(_labelFor(s)),
                  if (s == current) ...[
                    const Spacer(),
                    const Icon(Icons.check, size: 18),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
