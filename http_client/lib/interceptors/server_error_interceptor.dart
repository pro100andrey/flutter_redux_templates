import 'package:dio/dio.dart';

import '../http_settings.dart';
import '../responses/error_response.dart';

class ServerErrorInterceptor extends Interceptor {
  ServerErrorInterceptor({
    required this.httpSettings,
  });

  final HttpSettings httpSettings;

  @override
  void onError(DioError err, ErrorInterceptorHandler handler) {
    final response = err.response;

    if (response != null) {
      final error = ServerError.fromJson(
        response.data as Map<String, dynamic>,
      );

      if (response.statusCode == 401) {
        if (error.code == 1005 || error.code == 1001) {
          throw ServerSessionExpiredException();
        }
      }

      throw ServerErrorException(cause: error, code: response.statusCode ?? -1);
    }
  }
}
