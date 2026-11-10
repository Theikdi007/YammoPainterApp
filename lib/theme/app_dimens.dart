/// Spacing, radius and elevation tokens. Use these instead of magic numbers so
/// padding/rounding stays uniform across the redesigned screens.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

abstract final class AppElevation {
  static const double card = 2;
  static const double floating = 6;
}
