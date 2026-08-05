import 'package:dio/dio.dart';

import '../responses/error_response.dart';

/// Turns a server's error body into one of this package's typed exceptions and
/// hands it back through the handler.
///
/// Takes no settings. It used to require an `HttpSettings` it never read —
/// ceremony that also made it unconstructible in a test for no reason.
class ServerErrorInterceptor extends Interceptor {
  ServerErrorInterceptor();

  /// Codes the server uses to say the session is over rather than that the
  /// request was wrong. Both mean the same thing to the app: the token is no
  /// longer good.
  static const _sessionExpiredCodes = {1001, 1005};

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;

    // No response at all: timeout, DNS, socket. There is no body to read, and
    // calling no handler method leaves the request pending forever — the
    // caller's `await` neither completes nor throws.
    if (response == null) {
      handler.next(err);
      return;
    }

    // A 502 from a proxy is an HTML page, not JSON. Casting it replaces the
    // real failure with a TypeError raised from inside this interceptor.
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      handler.next(err);
      return;
    }

    final ServerError error;
    try {
      error = ServerError.fromJson(data);
    } on Object {
      // A JSON body that is not *this* shape is still not ours to interpret.
      handler.next(err);
      return;
    }

    final cause =
        response.statusCode == 401 && _sessionExpiredCodes.contains(error.code)
        ? ServerSessionExpiredException()
        : ServerErrorException(cause: error, code: response.statusCode ?? -1);

    // `reject`, not `throw`. Dio catches anything thrown from an interceptor
    // callback and wraps it in `DioException(type: unknown)`, after which
    // `error is ServerErrorException` is false at every catch site — and being
    // caught by type is the only reason these exceptions exist.
    handler.reject(
      DioException(requestOptions: err.requestOptions, error: cause),
    );
  }
}
