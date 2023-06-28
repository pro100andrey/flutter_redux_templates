import 'package:flutter/material.dart';

import '../generated/colors.gen.dart';

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: ColorName.primary,
        secondary: ColorName.secondary,
      ),
      inputDecorationTheme: inputDecorationTheme(),
    );

InputDecorationTheme inputDecorationTheme() {
  const borderRadius = BorderRadius.all(Radius.circular(28));

  return InputDecorationTheme(
    errorMaxLines: 10,
    border: const OutlineInputBorder(borderRadius: borderRadius),
    enabledBorder: const OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: ColorName.border),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
    focusColor: ColorName.primary,
  );
}
