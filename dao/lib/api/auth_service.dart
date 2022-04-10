import 'package:chopper/chopper.dart';


part 'auth_service.chopper.dart';

@ChopperApi()
abstract class AuthService extends ChopperService {
  // helper methods that help you instantiate your service
  static AuthService create([ChopperClient? client]) =>
      _$AuthService(client);

  @Post(path: 'login')
  Future<Response<String>> logIn({
    @Body() required Map<String, dynamic> body,
  });
}
