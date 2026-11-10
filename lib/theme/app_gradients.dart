import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Reusable gradients for the Vibrant Gradient look. Keeping them in one place
/// means hero banners, app bars and buttons stay visually in sync.
abstract final class AppGradients {
  /// The signature hero gradient: indigo → purple → pink. Used on app bars,
  /// banners and the home destinations.
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.accent, AppColors.pink],
  );

  /// Two-stop variant for buttons and smaller chips.
  static const LinearGradient button = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, AppColors.accent],
  );

  /// Cool accent for progress / success surfaces.
  static const LinearGradient cool = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.teal, AppColors.primary],
  );

  /// A faint top-to-bottom wash used behind whole screens in light mode.
  static const LinearGradient pageLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF1EEFF), AppColors.lightSurface],
  );

  /// Page wash for dark mode.
  static const LinearGradient pageDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1B1830), AppColors.darkSurface],
  );

  /// Bottom-anchored scrim for overlaying controls on a camera/photo.
  static const LinearGradient bottomScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000)],
  );
}
