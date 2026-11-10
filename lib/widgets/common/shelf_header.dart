import 'package:flutter/material.dart';

/// A consistent shelf/section title: a bold title (theme on-surface color), an
/// optional muted count, and an optional trailing action (e.g. "See all").
class ShelfHeader extends StatelessWidget {
  const ShelfHeader(
    this.title, {
    super.key,
    this.count,
    this.action,
  });

  final String title;

  /// Optional number shown muted after the title (e.g. a story/photo count).
  final int? count;

  /// Optional trailing widget, right-aligned.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const Spacer(),
        ?action,
      ],
    );
  }
}
