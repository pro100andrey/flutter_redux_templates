// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

part of 'colors.dart';

// **************************************************************************
// ThemeExtensionsGenerator
// **************************************************************************

mixin _$ThemeExtensionMixin on ThemeExtension<ColorsThemeExtension> {
  @override
  ThemeExtension<ColorsThemeExtension> copyWith({
    Color? primary,
    Color? secondary,
    Color? background,
    Color? error,
    Color? shade,
    Color? border,
  }) {
    final object = this as ColorsThemeExtension;

    return ColorsThemeExtension(
      primary: primary ?? object.primary,
      secondary: secondary ?? object.secondary,
      background: background ?? object.background,
      error: error ?? object.error,
      shade: shade ?? object.shade,
      border: border ?? object.border,
    );
  }

  @override
  ThemeExtension<ColorsThemeExtension> lerp(
    ThemeExtension<ColorsThemeExtension>? other,
    double t,
  ) {
    final otherValue = other;

    if (otherValue is! ColorsThemeExtension) {
      return this;
    }

    final value = this as ColorsThemeExtension;

    return ColorsThemeExtension(
      primary: Color.lerp(value.primary, otherValue.primary, t)!,
      secondary: Color.lerp(value.secondary, otherValue.secondary, t)!,
      background: Color.lerp(value.background, otherValue.background, t)!,
      error: Color.lerp(value.error, otherValue.error, t)!,
      shade: Color.lerp(value.shade, otherValue.shade, t)!,
      border: Color.lerp(value.border, otherValue.border, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    final value = this as ColorsThemeExtension;

    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ColorsThemeExtension &&
            identical(value.primary, other.primary) &&
            identical(value.secondary, other.secondary) &&
            identical(value.background, other.background) &&
            identical(value.error, other.error) &&
            identical(value.shade, other.shade) &&
            identical(value.border, other.border));
  }

  @override
  int get hashCode {
    final value = this as ColorsThemeExtension;

    return Object.hash(
      runtimeType,
      value.primary,
      value.secondary,
      value.background,
      value.error,
      value.shade,
      value.border,
    );
  }
}

extension ColorsThemeExtensionBuildContext on BuildContext {
  ColorsThemeExtension get colorsTheme =>
      Theme.of(this).extension<ColorsThemeExtension>()!;
}
