import 'package:flutter/material.dart';

ThemeData darkTheme() => ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.blue[900],
    );

ThemeData lightTheme() => ThemeData.light().copyWith(
      scaffoldBackgroundColor: Colors.white,
    );
