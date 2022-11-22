import 'package:freezed_annotation/freezed_annotation.dart';

class BoolConverter implements JsonConverter<bool, Object> {
  const BoolConverter();

  @override
  bool fromJson(Object value) {
    if (value is int) {
      return value != 0;
    } else {
      throw ArgumentError('Invalid bool value: $value');
    }
  }

  @override
  Object toJson(bool value) => value ? 1 : 0;
}

class OptionalBoolConverter implements JsonConverter<bool?, Object?> {
  const OptionalBoolConverter();

  @override
  bool? fromJson(Object? value) =>
      value == null ? null : BoolConverter().fromJson(value);

  @override
  Object? toJson(bool? value) =>
      value == null ? null : BoolConverter().toJson(value);
}
