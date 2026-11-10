import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// Builds the app's [ThemeData] for light and dark mode from the brand tokens
/// in [AppColors]. Both share one builder so component styling (cards, chips,
/// sliders, nav bar) stays identical apart from the color scheme.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Seed from the brand primary, then punch up secondary/tertiary so the
    // vibrant gradient accents read through Material's tonal palette.
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.primary,
          secondary: AppColors.teal,
          tertiary: AppColors.pink,
          error: AppColors.danger,
          surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,

      // App bars are transparent by default — screens paint their own gradient
      // header via GradientAppBar; this keeps the fallback consistent.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        elevation: 0,
        backgroundColor: isDark
            ? AppColors.darkSurfaceAlt
            : AppColors.lightSurfaceAlt,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: AppElevation.card,
        color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),

      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withValues(alpha: 0.18),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.16),
        trackHeight: 4,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceAlt
            : AppColors.lightSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceAlt
            : AppColors.lightSurfaceAlt,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
