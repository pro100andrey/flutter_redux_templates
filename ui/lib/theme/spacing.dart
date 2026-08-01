import 'package:flutter/widgets.dart';

/// The spacing scale — layer 3 of the theme strategy (see `common.dart`).
///
/// A 4-point scale, doubling from [sm]. A value off the scale is a smell: the
/// point is that screens built from these line up with each other.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Ready-made gaps, so a layout reads as rhythm rather than arithmetic.
abstract final class Gaps {
  /// Vertical — the common case, since columns dominate these layouts.
  static const Widget xs = SizedBox(height: AppSpacing.xs);
  static const Widget sm = SizedBox(height: AppSpacing.sm);
  static const Widget md = SizedBox(height: AppSpacing.md);
  static const Widget lg = SizedBox(height: AppSpacing.lg);
  static const Widget xl = SizedBox(height: AppSpacing.xl);

  /// Horizontal, for a `Row`.
  static const Widget hXs = SizedBox(width: AppSpacing.xs);
  static const Widget hSm = SizedBox(width: AppSpacing.sm);
  static const Widget hMd = SizedBox(width: AppSpacing.md);
  static const Widget hLg = SizedBox(width: AppSpacing.lg);
  static const Widget hXl = SizedBox(width: AppSpacing.xl);
}

/// Padding built from the same scale.
abstract final class Insets {
  static const sm = EdgeInsets.all(AppSpacing.sm);
  static const md = EdgeInsets.all(AppSpacing.md);
  static const lg = EdgeInsets.all(AppSpacing.lg);

  /// Screen-edge padding: generous horizontally, tighter vertically.
  static const screen = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.lg,
  );
}
