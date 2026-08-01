import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:localization/localization.dart';

import '../models/value_changed.dart';
import 'segmented_control.dart';

/// Light/dark switcher.
///
/// `ThemeMode.system` has no segment: with three modes and two segments the
/// control would sit with neither selected, which reads as a bug. A screen that
/// needs "follow the OS" wants a three-item list, not this.
class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({required this.vm, super.key});

  final FieldVm<ThemeMode> vm;

  @override
  Widget build(BuildContext context) => SegmentedControl<ThemeMode>(
    vm: vm,
    segments: [
      Segment(value: .dark, icon: LucideIcons.moon, label: S.current.darkTheme),
      Segment(
        value: .light,
        icon: LucideIcons.sun,
        label: S.current.lightTheme,
      ),
    ],
  );
}
