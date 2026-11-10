import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';

/// An animated shimmer box — a soft moving highlight over a muted fill, used as
/// a skeleton placeholder while content loads. Brightness-aware so it reads on
/// both the light page and dark mode.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.85);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value; // 0..1
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + v, -1),
              end: Alignment(1 + v, 1),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// A story-card skeleton that matches the [StoryCard] footprint for shelf
/// loading placeholders. Defaults to the legacy wide (16:9) shape; pass
/// `compact: true` for the square-cover grid card used by the redesigned shelf.
class StoryCardSkeleton extends StatelessWidget {
  const StoryCardSkeleton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: compact ? 1 : 16 / 9,
            child: const ShimmerBox(radius: 0),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              10,
              compact ? 8 : 14,
              10,
              compact ? 10 : 14,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShimmerBox(height: 13, width: double.infinity, radius: 4),
                      const SizedBox(height: 6),
                      ShimmerBox(height: 11, width: 44, radius: 4),
                    ],
                  )
                : ShimmerBox(height: 14, width: 140, radius: 4),
          ),
        ],
      ),
    );
  }
}
