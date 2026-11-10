import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// A frosted, translucent card — the core surface of the Vibrant Gradient look.
///
/// Blurs whatever sits behind it (a gradient, a camera feed, a photo) and lays
/// a faint white film + hairline stroke on top. Use it for floating chrome and
/// list cards that sit over colorful backgrounds.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.borderRadius,
    this.onTap,
    this.blur = 14,
    this.tint,
    this.strokeColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final double blur;
  final Color? tint;
  final Color? strokeColor;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.lg);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                tint ??
                (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.55)),
            borderRadius: radius,
            border: Border.all(
              color: strokeColor ?? AppColors.glassStroke,
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
