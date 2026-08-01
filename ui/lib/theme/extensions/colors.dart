import 'package:flutter/material.dart';
import 'package:theme_extensions_builder_annotation/theme_extensions_builder_annotation.dart';

part 'colors.g.theme.dart';

/// Brand colors that vary by theme and have no Material role.
///
/// Read via `context.colors`. Anything with a role belongs in `ColorScheme`
/// instead — see the layer rules in `theme/common.dart`.
@ThemeExtensions(contextAccessorName: 'colors')
class AppColors extends ThemeExtension<AppColors> with _$AppColors {
  const AppColors({required this.borderStrong});

  /// Boundary around an interactive control, a step stronger than `outline`.
  final Color borderStrong;
}
