import 'package:flutter/material.dart';

import '../export.dart';

ThemeData darkTheme() => ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.blue[900],
    );

ThemeData lightTheme() => ThemeData.light().copyWith(
      colorScheme: const ColorScheme.light(
        primary: ColorName.primary,
        secondary: ColorName.secondary,
      ),
    );
