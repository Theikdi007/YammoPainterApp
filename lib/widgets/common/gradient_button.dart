import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_gradients.dart';

/// A full-width-friendly gradient action button. Disabled state (null
/// [onPressed]) flattens to a muted surface so it reads as inactive without
/// losing its shape.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.gradient = AppGradients.button,
    this.height = 54,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final double height;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !loading;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          )
        else if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (!loading)
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: enabled ? gradient : null,
          color: enabled ? null : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Center(child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
