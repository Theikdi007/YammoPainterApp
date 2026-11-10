import 'package:flutter/material.dart';

/// Central color tokens for the **Vibrant Gradient** design direction.
///
/// Raw brand colors live here; [AppTheme] turns them into Material 3
/// [ColorScheme]s. Reach for these constants only when you need a *specific*
/// brand color (e.g. a gradient stop); for everything else prefer
/// `Theme.of(context).colorScheme.*` so light/dark stay consistent.
abstract final class AppColors {
  // --- Brand seeds -----------------------------------------------------------
  /// Indigo-violet — the primary brand hue and gradient anchor.
  static const Color primary = Color(0xFF6C5CE7);
  static const Color primaryDeep = Color(0xFF5341D6);

  /// Magenta/purple — second gradient stop on hero surfaces.
  static const Color accent = Color(0xFFA855F7);

  /// Pink — third gradient stop / playful highlight.
  static const Color pink = Color(0xFFEC4899);

  /// Teal — the cool secondary used for success / progress accents.
  static const Color teal = Color(0xFF00C2CB);

  /// Warm amber — used sparingly for "active" toggles (flash, locks).
  static const Color amber = Color(0xFFFFB020);

  static const Color danger = Color(0xFFFF5470);

  // --- Neutral surfaces ------------------------------------------------------
  static const Color lightSurface = Color(0xFFF7F6FC);
  static const Color lightSurfaceAlt = Color(0xFFFFFFFF);
  static const Color darkSurface = Color(0xFF14131C);
  static const Color darkSurfaceAlt = Color(0xFF1E1C2A);

  // --- Glass overlays --------------------------------------------------------
  /// Translucent fills used by [GlassCard] / floating chrome.
  static const Color glassLight = Color(0x14FFFFFF); // ~8% white
  static const Color glassStroke = Color(0x33FFFFFF); // ~20% white
  static const Color scrim = Color(0x66000000);
}
