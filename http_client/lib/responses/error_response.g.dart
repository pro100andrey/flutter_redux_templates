// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ServerError _$ServerErrorFromJson(Map<String, dynamic> json) => _ServerError(
  type: json['type'] as String,
  errors: IList<ErrorItem>.fromJson(
    json['errors'],
    (value) => ErrorItem.fromJson(value as Map<String, dynamic>),
  ),
  code: (json['code'] as num).toInt(),
);

Map<String, dynamic> _$ServerErrorToJson(_ServerError instance) =>
    <String, dynamic>{
      'type': instance.type,
      'errors': instance.errors.toJson((value) => value),
      'code': instance.code,
    };

_ErrorItem _$ErrorItemFromJson(Map<String, dynamic> json) => _ErrorItem(
  source: json['source'] as String?,
  detail: json['detail'] as String,
);

Map<String, dynamic> _$ErrorItemToJson(_ErrorItem instance) =>
    <String, dynamic>{
      if (instance.source case final value?) 'source': value,
      'detail': instance.detail,
    };
