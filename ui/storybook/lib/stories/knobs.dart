import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/alerts/styled_snackbar.dart';

extension BuildContextEx on BuildContext {
  VoidCallback? knobOnPressed([
    String label = 'Enabled',
  ]) =>
      knobs.boolean(label: label)
          ? () => showStyledSnackbar(
                context: this,
                title: label,
                message: 'On Pressed',
              )
          : null;

  ValueChanged<T>? knobOnValueChanged<T>([
    String label = 'Enabled',
  ]) =>
      knobs.boolean(label: label)
          ? (v) => showStyledSnackbar(
                context: this,
                title: label,
                message: v.toString(),
              )
          : null;

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
