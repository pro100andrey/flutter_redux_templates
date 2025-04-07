import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../bodies/login_body.dart';

part 'auth.g.dart';

@RestApi()
abstract class AuthService {
  // helper methods that help you instantiate your service
  factory AuthService(Dio dio, {required String baseUrl}) = _AuthService;

  @POST('/api/account/login')
  Future<void> logIn({@Body() required LoginBody body});

  @POST('/api/account/logout')
  Future<void> logOut();
}
