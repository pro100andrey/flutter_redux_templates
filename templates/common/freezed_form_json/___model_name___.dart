import 'package:freezed_annotation/freezed_annotation.dart';

part '___model_name___.freezed.dart';
part '___model_name___.g.dart';

@freezed
abstract class ___ModelName___ with _$___ModelName___ {
  factory ___ModelName___({required int id}) = ____ModelName___;

  factory ___ModelName___.fromJson(Map<String, dynamic> json) =>
      _$___ModelName___FromJson(json);
}
