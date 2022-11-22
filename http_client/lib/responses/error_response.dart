import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'error_response.freezed.dart';
part 'error_response.g.dart';

@freezed
class ServerError with _$ServerError {
  factory ServerError({
    required String type,
    required IList<ErrorItem> errors,
    required int code,
  }) = _ServerError;

  factory ServerError.fromJson(Map<String, dynamic> json) =>
      _$ServerErrorFromJson(json);
}

@freezed
class ErrorItem with _$ErrorItem {
  factory ErrorItem({
    required String? source,
    required String detail,
  }) = _ErrorItem;

  factory ErrorItem.fromJson(Map<String, dynamic> json) =>
      _$ErrorItemFromJson(json);
}

class ServerErrorException implements Exception {
  ServerErrorException({
    required this.cause,
    required this.code,
  });

  ServerError cause;
  int code;
}

class CustomServerException implements Exception {
  CustomServerException();
}

class ServerSessionExpiredException implements CustomServerException {
  ServerSessionExpiredException();
}

class ServerInvalidLinkException implements CustomServerException {
  ServerInvalidLinkException();
}
