import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_body.freezed.dart';
part 'login_body.g.dart';

@Freezed()
abstract class LoginBody with _$LoginBody {
  factory LoginBody({required String email, required String password}) =
      _LoginBody;

  factory LoginBody.fromJson(Map<String, dynamic> json) =>
      _$LoginBodyFromJson(json);
}
