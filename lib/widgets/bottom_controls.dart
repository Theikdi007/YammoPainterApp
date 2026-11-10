import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'common/glass_card.dart';

/// Floating control panel for the AR Drawing screen: an opacity slider plus
/// camera / flash actions, presented as a frosted glass card over the live
/// camera feed.
class BottomControls extends StatelessWidget {
  const BottomControls({
    super.key,
    required this.opacity,
    required this.onOpacityChanged,
    required this.onCameraToggle,
    required this.onFlashlightToggle,
    required this.flashlightOn,
    required this.hasCamera,
  });

  final double opacity;
  final ValueChanged<double> onOpacityChanged;
  final VoidCallback onCameraToggle;
  final VoidCallback onFlashlightToggle;
  final bool flashlightOn;
  final bool hasCamera;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: GlassCard(
        tint: Colors.black.withValues(alpha: 0.35),
        strokeColor: Colors.white.withValues(alpha: 0.18),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.opacity, color: Colors.white70, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                    ),
                    child: Slider(
                      min: 0.0,
                      max: 1.0,
                      value: opacity,
                      onChanged: onOpacityChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(opacity * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionIcon(
                  icon: Icons.flip_camera_android,
                  label: 'Flip camera',
                  onTap: hasCamera ? onCameraToggle : null,
                ),
                _ActionIcon(
                  icon: Icons.flashlight_on,
                  label: 'Flash',
                  isActive: flashlightOn,
                  onTap: hasCamera ? onFlashlightToggle : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? AppColors.amber
        : (onTap == null ? Colors.white38 : Colors.white);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.amber.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? AppColors.amber.withValues(alpha: 0.6)
                    : Colors.transparent,
              ),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: onTap == null ? Colors.white38 : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
