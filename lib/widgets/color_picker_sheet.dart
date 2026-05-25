import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Modal bottom sheet wrapping the `flutter_colorpicker` HSV wheel.
///
/// Returns the picked color, or `null` if the user cancelled. The
/// controller's `openColorPicker` is the only intended caller.
Future<Color?> showColorPickerSheet({
  required BuildContext context,
  required Color initial,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return _ColorPickerBody(initial: initial);
    },
  );
}

class _ColorPickerBody extends StatefulWidget {
  const _ColorPickerBody({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerBody> createState() => _ColorPickerBodyState();
}

class _ColorPickerBodyState extends State<_ColorPickerBody> {
  late Color _current = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pick a color',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ColorPicker(
              pickerColor: _current,
              onColorChanged: (c) => setState(() => _current = c),
              enableAlpha: false,
              displayThumbColor: true,
              labelTypes: const [],
              pickerAreaHeightPercent: 0.7,
              hexInputBar: true,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_current),
                    child: const Text('Use'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
