import 'package:freezed_annotation/freezed_annotation.dart';

part '___model_name___.freezed.dart';
part '___model_name___.g.dart';

@freezed
abstract class ___ModelName___ with _$___ModelName___ {
  factory ___ModelName___({
    required String type,
    required int id,
    required ___ModelName___Attributes attributes,
  }) = ____ModelName___;

  factory ___ModelName___.fromJson(Map<String, dynamic> json) =>
      _$___ModelName___FromJson(json);
}

@freezed
abstract class ___ModelName___Attributes with _$___ModelName___Attributes {
  factory ___ModelName___Attributes({required String name}) =
      ____ModelName___Attributes;

  factory ___ModelName___Attributes.fromJson(Map<String, dynamic> json) =>
      _$___ModelName___AttributesFromJson(json);
}
