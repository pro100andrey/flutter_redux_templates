import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.freezed.dart';
part 'session.g.dart';

@freezed
class Session with _$Session {
  factory Session({
    @JsonKey(name: 'token') required String token,
  }) = _Session;

  factory Session.fromJson(Map<String, dynamic> json) =>
      _$SessionFromJson(json);
}
