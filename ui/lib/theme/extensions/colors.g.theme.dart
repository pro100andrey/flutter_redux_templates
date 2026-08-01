// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

part of 'colors.dart';

// **************************************************************************
// ThemeExtensionsGenerator
// **************************************************************************

mixin _$AppColors on ThemeExtension<AppColors> {
  @override
  ThemeExtension<AppColors> copyWith({Color? borderStrong}) {
    final _this = (this as AppColors);

    return AppColors(borderStrong: borderStrong ?? _this.borderStrong);
  }

  @override
  ThemeExtension<AppColors> lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }

    final _this = (this as AppColors);

    return AppColors(
      borderStrong: Color.lerp(_this.borderStrong, other.borderStrong, t)!,
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

    final _this = (this as AppColors);
    final _other = (other as AppColors);

    return _other.borderStrong == _this.borderStrong;
  }

  @override
  int get hashCode {
    final _this = (this as AppColors);

    return Object.hash(runtimeType, _this.borderStrong);
  }
}

extension AppColorsBuildContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
