// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$_ServerError _$$_ServerErrorFromJson(Map<String, dynamic> json) =>
    _$_ServerError(
      type: json['type'] as String,
      errors: IList<ErrorItem>.fromJson(json['errors'],
          (value) => ErrorItem.fromJson(value as Map<String, dynamic>)),
      code: json['code'] as int,
    );

Map<String, dynamic> _$$_ServerErrorToJson(_$_ServerError instance) =>
    <String, dynamic>{
      'type': instance.type,
      'errors': instance.errors.toJson(
        (value) => value,
      ),
      'code': instance.code,
    };

_$_ErrorItem _$$_ErrorItemFromJson(Map<String, dynamic> json) => _$_ErrorItem(
      source: json['source'] as String?,
      detail: json['detail'] as String,
    );

Map<String, dynamic> _$$_ErrorItemToJson(_$_ErrorItem instance) =>
    <String, dynamic>{
      'source': instance.source,
      'detail': instance.detail,
    };
