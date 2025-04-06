import 'package:flutter/material.dart';
import 'package:theme_extensions_builder_annotation/theme_extensions_builder_annotation.dart';

part '../../theme_extension/___extension_name____theme.g.dart';

/// getter: final theme = context.___extensionName___Theme
@themeExtensions
class ___ExtensionName___Theme extends ThemeExtension<___ExtensionName___Theme>
    with _$ThemeExtensionMixin {
  const ___ExtensionName___Theme({this.color = Colors.red});

  final Color? color;
}
