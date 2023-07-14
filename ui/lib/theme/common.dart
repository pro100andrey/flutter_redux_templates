import 'package:flutter/material.dart';

import '../generated/colors.gen.dart';

ThemeData _base = ThemeData(
  useMaterial3: true,
);

ThemeData buildTheme() => _base.copyWith(
      inputDecorationTheme: inputDecorationTheme(),
      dialogTheme: dialogTheme(),
      elevatedButtonTheme: elevatedButtonTheme(),
    );

ElevatedButtonThemeData elevatedButtonTheme() => ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(),
    );

DialogTheme dialogTheme() => _base.dialogTheme.copyWith();

InputDecorationTheme inputDecorationTheme() {
  const borderRadius = BorderRadius.all(Radius.circular(28));

  return _base.inputDecorationTheme.copyWith(
    isDense: true,
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
