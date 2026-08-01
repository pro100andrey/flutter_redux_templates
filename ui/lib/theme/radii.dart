import 'package:flutter/widgets.dart';

/// Corner-radius tokens — layer 3 of the theme strategy (see `common.dart`).
///
/// Not a `ThemeExtension`: the values are the same in both themes, so there is
/// nothing to interpolate. Promote it if two themes ever need different corner
/// treatments.
abstract final class AppRadii {
  /// A segment inside a control, e.g. the theme switcher's halves.
  static const double segment = 6;

  /// A control that groups segments.
  static const double control = 8;

  static const double input = 9;
  static const double button = 9;

  /// The card that holds a form.
  static const double card = 14;
}

/// The same tokens as ready `BorderRadius`, so a widget does not restate
/// `BorderRadius.circular` at every call.
abstract final class Radii {
  static const segment = BorderRadius.all(Radius.circular(AppRadii.segment));
  static const control = BorderRadius.all(Radius.circular(AppRadii.control));
  static const input = BorderRadius.all(Radius.circular(AppRadii.input));
  static const button = BorderRadius.all(Radius.circular(AppRadii.button));
  static const card = BorderRadius.all(Radius.circular(AppRadii.card));
}
