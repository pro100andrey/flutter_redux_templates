import 'package:flutter/material.dart';

import '../assets.dart';

ThemeData buildTheme() => ThemeData.light().copyWith(
      colorScheme: const ColorScheme.light(
        primary: ColorName.primary,
        secondary: ColorName.secondary,
      ),
      inputDecorationTheme: inputDecorationTheme(),
    );

InputDecorationTheme inputDecorationTheme() {
  const borderRadius = BorderRadius.all(Radius.circular(28));
  return const InputDecorationTheme(
    focusedBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: ColorName.primary,
      ),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: ColorName.error,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: ColorName.border,
      ),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: ColorName.shade,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: ColorName.primary,
      ),
    ),
    errorMaxLines: 10,
  );
}
