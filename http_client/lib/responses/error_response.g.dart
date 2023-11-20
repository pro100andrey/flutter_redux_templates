// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ServerErrorImpl _$$ServerErrorImplFromJson(Map<String, dynamic> json) =>
    _$ServerErrorImpl(
      type: json['type'] as String,
      errors: IList<ErrorItem>.fromJson(json['errors'],
          (value) => ErrorItem.fromJson(value as Map<String, dynamic>)),
      code: json['code'] as int,
    );

Map<String, dynamic> _$$ServerErrorImplToJson(_$ServerErrorImpl instance) =>
    <String, dynamic>{
      'type': instance.type,
      'errors': instance.errors.toJson(
        (value) => value,
      ),
      'code': instance.code,
    };

_$ErrorItemImpl _$$ErrorItemImplFromJson(Map<String, dynamic> json) =>
    _$ErrorItemImpl(
      source: json['source'] as String?,
      detail: json['detail'] as String,
    );

Map<String, dynamic> _$$ErrorItemImplToJson(_$ErrorItemImpl instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('source', instance.source);
  val['detail'] = instance.detail;
  return val;
}
