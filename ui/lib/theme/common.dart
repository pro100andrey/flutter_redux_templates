import 'package:flutter/material.dart';

import '../generated/colors.gen.dart';
import 'extensions/colors.dart';

ColorsThemeExtension _lightColors = const ColorsThemeExtension(
  primary: ColorName.lightPrimary,
  secondary: ColorName.lightSecondary,
  background: ColorName.lightBackground,
  error: ColorName.lightError,
  shade: ColorName.lightShade,
  border: ColorName.lightBorder,
);

ColorsThemeExtension _darkColors = const ColorsThemeExtension(
  primary: ColorName.darkPrimary,
  secondary: ColorName.darkSecondary,
  background: ColorName.darkBackground,
  error: ColorName.darkError,
  shade: ColorName.darkShade,
  border: ColorName.darkBorder,
);

ThemeData lightTheme() {
  final theme = ThemeData.light(useMaterial3: true).copyWith(
    primaryColor: _lightColors.primary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.pink,
      primary: _lightColors.primary,
      secondary: _lightColors.secondary,
    ),
  );

  return theme.copyWith(
    inputDecorationTheme: inputDecorationTheme(
      theme.inputDecorationTheme,
      _lightColors,
    ),
    extensions: [_lightColors],
  );
}

ThemeData darkTheme() {
  final theme = ThemeData.dark(useMaterial3: true).copyWith(
    primaryColor: _lightColors.primary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.pink,
      primary: _lightColors.primary,
      secondary: _lightColors.secondary,
    ),
  );

  return theme.copyWith(
    inputDecorationTheme: inputDecorationTheme(
      theme.inputDecorationTheme,
      _darkColors,
    ),
    extensions: [_darkColors],
  );
}

InputDecorationTheme inputDecorationTheme(
  InputDecorationTheme theme,
  ColorsThemeExtension colors,
) {
  const borderRadius = BorderRadius.all(Radius.circular(28));

  return theme.copyWith(
    isDense: true,
    errorMaxLines: 10,
    border: const OutlineInputBorder(borderRadius: borderRadius),
    enabledBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colors.border),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colors.border),
    ),
    focusColor: colors.primary,
  );
}
