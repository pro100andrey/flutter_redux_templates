import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/alerts/styled_snackbar.dart';

extension BuildContextEx on BuildContext {
  VoidCallback? knobOnPressedOptional({
    String label = 'Enabled',
    bool initial = true,
  }) =>
      knobs.boolean(label: label, initial: initial)
          ? () => showStyledSnackbar(
                context: this,
                title: label,
                message: 'On Pressed',
              )
          : null;

  VoidCallback knobOnPressed({
    String label = 'Some pressed',
  }) =>
      () => showStyledSnackbar(
            context: this,
            title: label,
            message: 'On Pressed',
          );


  String? knobInputError([
    String label = 'Input Error',
  ]) =>
      knobs.boolean(label: label) ? label : null;

  bool knobIsWaiting() => knobs.boolean(label: 'isWaiting');

  String knobWords({
    required String label,
    int initial = 1,
    int max = 500,
  }) {
    final count = knobs.sliderInt(
      label: label,
      min: 1,
      initial: initial,
      max: max,
    );
    return _words.take(count).join(' ');
  }
}

final _words = generateWordPairs().take(500).toList();
