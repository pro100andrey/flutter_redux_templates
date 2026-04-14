// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

part of 'colors.dart';

// **************************************************************************
// ThemeExtensionsGenerator
// **************************************************************************

mixin _$ColorsThemeExtension on ThemeExtension<ColorsThemeExtension> {
  @override
  ThemeExtension<ColorsThemeExtension> copyWith({
    Color? primary,
    Color? secondary,
    Color? background,
    Color? error,
    Color? shade,
    Color? border,
  }) {
    final _this = (this as ColorsThemeExtension);

    return ColorsThemeExtension(
      primary: primary ?? _this.primary,
      secondary: secondary ?? _this.secondary,
      background: background ?? _this.background,
      error: error ?? _this.error,
      shade: shade ?? _this.shade,
      border: border ?? _this.border,
    );
  }

  @override
  ThemeExtension<ColorsThemeExtension> lerp(
    ThemeExtension<ColorsThemeExtension>? other,
    double t,
  ) {
    if (other is! ColorsThemeExtension) {
      return this;
    }

    final _this = (this as ColorsThemeExtension);

    return ColorsThemeExtension(
      primary: Color.lerp(_this.primary, other.primary, t)!,
      secondary: Color.lerp(_this.secondary, other.secondary, t)!,
      background: Color.lerp(_this.background, other.background, t)!,
      error: Color.lerp(_this.error, other.error, t)!,
      shade: Color.lerp(_this.shade, other.shade, t)!,
      border: Color.lerp(_this.border, other.border, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    if (other.runtimeType != runtimeType) {
      return false;
    }

    final _this = (this as ColorsThemeExtension);
    final _other = (other as ColorsThemeExtension);

    return _other.primary == _this.primary &&
        _other.secondary == _this.secondary &&
        _other.background == _this.background &&
        _other.error == _this.error &&
        _other.shade == _this.shade &&
        _other.border == _this.border;
  }

  @override
  int get hashCode {
    final _this = (this as ColorsThemeExtension);

    return Object.hash(
      runtimeType,
      _this.primary,
      _this.secondary,
      _this.background,
      _this.error,
      _this.shade,
      _this.border,
    );
  }
}

extension ColorsThemeExtensionBuildContext on BuildContext {
  ColorsThemeExtension get colorsTheme =>
      Theme.of(this).extension<ColorsThemeExtension>()!;
}
