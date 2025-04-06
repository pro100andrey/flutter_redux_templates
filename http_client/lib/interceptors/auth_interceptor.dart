import 'package:dio/dio.dart';

import '../http_settings.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.httpSettings});

  final HttpSettings httpSettings;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = httpSettings.authBearerToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
