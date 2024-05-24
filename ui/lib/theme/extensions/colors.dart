import 'package:flutter/material.dart';
import 'package:theme_extensions_builder_annotation/theme_extensions_builder_annotation.dart';

part 'colors.g.theme.dart';

@themeExtensions
class ColorsThemeExtension extends ThemeExtension<ColorsThemeExtension>
    with _$ThemeExtensionMixin {
  const ColorsThemeExtension({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.error,
    required this.shade,
    required this.border,
  });

  final Color primary;
  final Color secondary;
  final Color background;
  final Color error;
  final Color shade;
  final Color border;
}
