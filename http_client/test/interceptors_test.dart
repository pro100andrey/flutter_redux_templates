import 'package:dio/dio.dart';
import 'package:http_client/http_settings.dart';
import 'package:http_client/interceptors/auth_interceptor.dart';
import 'package:http_client/interceptors/server_error_interceptor.dart';
import 'package:http_client/responses/error_response.dart';
import 'package:test/test.dart';

/// Captures which handler method an interceptor called, and with what.
///
/// A hand-rolled double rather than a mocking package:
/// `ErrorInterceptorHandler` has three outcomes worth telling apart — `next`
/// (pass along), `reject` (fail with this), `resolve` (succeed anyway) — and
/// the whole point of these tests is *which one* was reached. A matcher on a
/// mock would say the same thing less clearly, and this package has no mocking
/// dependency to add.
class _Handler extends ErrorInterceptorHandler {
  DioException? nexted;
  DioException? rejected;

  @override
  void next(DioException err) => nexted = err;

  @override
  void reject(DioException err, [bool callFollowingErrorInterceptor = false]) =>
      rejected = err;
}

RequestOptions _request() => RequestOptions(path: '/whatever');

DioException _failure({Object? body, int? status}) => DioException(
  requestOptions: _request(),
  response: body == null && status == null
      ? null
      : Response<Object?>(
          requestOptions: _request(),
          data: body,
          statusCode: status,
        ),
);

Map<String, Object?> _serverError({required int code}) => {
  'type': 'about:blank',
  'errors': [
    {'source': 'email', 'detail': 'must be an email'},
  ],
  'code': code,
};

void main() {
  group('AuthInterceptor', () {
    test('adds the bearer header when the token reader returns one', () {
      final options = _request();
      AuthInterceptor(
        httpSettings: HttpSettings(authBearerToken: () => 'abc'),
      ).onRequest(options, RequestInterceptorHandler());

      expect(options.headers['Authorization'], 'Bearer abc');
    });

    test('adds no header when there is no token', () {
      final options = _request();
      AuthInterceptor(
        httpSettings: HttpSettings(authBearerToken: () => null),
      ).onRequest(options, RequestInterceptorHandler());

      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    test('reads the token per request, not once at construction', () {
      // The reason `Authorization` is a callback and not a String: the token
      // arrives after login, and a client built at boot must pick it up
      // without being rebuilt.
      String? token;
      final interceptor = AuthInterceptor(
        httpSettings: HttpSettings(authBearerToken: () => token),
      );

      final before = _request();
      interceptor.onRequest(before, RequestInterceptorHandler());
      expect(before.headers.containsKey('Authorization'), isFalse);

      token = 'arrived';
      final after = _request();
      interceptor.onRequest(after, RequestInterceptorHandler());
      expect(after.headers['Authorization'], 'Bearer arrived');
    });
  });

  group('ServerErrorInterceptor', () {
    test('a 401 with an expiry code rejects with the session exception', () {
      final handler = _Handler();
      ServerErrorInterceptor().onError(
        _failure(body: _serverError(code: 1005), status: 401),
        handler,
      );

      expect(handler.rejected?.error, isA<ServerSessionExpiredException>());
    });

    test('any other server error rejects carrying the parsed body', () {
      final handler = _Handler();
      ServerErrorInterceptor().onError(
        _failure(body: _serverError(code: 42), status: 500),
        handler,
      );

      final error = handler.rejected?.error;
      expect(error, isA<ServerErrorException>());
      expect((error! as ServerErrorException).code, 500);
      expect(
        (error as ServerErrorException).cause.errors.first.detail,
        'must be an email',
      );
    });

    test('rejects rather than throws, so the type survives to the caller', () {
      // Throwing from a Dio callback does not reach the caller as itself: Dio
      // catches it and wraps it in `DioException(type: unknown)`, after which
      // `error is ServerErrorException` is false at every catch site. The
      // typed exceptions exist to be caught by type, so this is the assertion
      // the whole file is about.
      final handler = _Handler();
      expect(
        () => ServerErrorInterceptor().onError(
          _failure(body: _serverError(code: 42), status: 500),
          handler,
        ),
        returnsNormally,
      );
      expect(handler.rejected, isNotNull);
    });

    test('a transport failure with no response is passed along', () {
      // Timeout, DNS, socket: `err.response` is null. Calling no handler
      // method at all leaves the request pending forever — the caller's
      // `await` never completes and never throws.
      final handler = _Handler();
      ServerErrorInterceptor().onError(_failure(), handler);

      expect(handler.nexted, isNotNull);
      expect(handler.rejected, isNull);
    });

    test('a non-JSON error body is passed along, not cast', () {
      // A 502 from a proxy is an HTML page. Casting it to a Map replaces the
      // real failure with a TypeError from inside the interceptor.
      final handler = _Handler();
      ServerErrorInterceptor().onError(
        _failure(body: '<html>502 Bad Gateway</html>', status: 502),
        handler,
      );

      expect(handler.nexted, isNotNull);
    });
  });

  group('ServerError', () {
    test('parses the wire shape', () {
      final error = ServerError.fromJson(_serverError(code: 1001));

      expect(error.code, 1001);
      expect(error.errors, hasLength(1));
      expect(error.errors.first.source, 'email');
    });
  });
}
