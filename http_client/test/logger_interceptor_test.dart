import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_client/interceptors/logger_interceptor.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Answers every request with one canned body, so a test drives the real Dio
/// pipeline — interceptors included — without a socket.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {required this.contentType});

  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [contentType],
      'set-cookie': ['session=abc123'],
    },
  );

  @override
  void close({bool force = false}) {}
}

Dio _dio(String body, {required String contentType}) =>
    Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _Adapter(body, contentType: contentType)
      ..interceptors.add(LoggerInterceptor());

/// The logger sits in every request's path, so anything it throws fails the
/// request — and anything it prints lands in the console and the app's logs.
void main() {
  final lines = <String>[];

  setUpAll(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((r) => lines.add(r.message));
  });

  setUp(lines.clear);

  group('a successful response stays successful', () {
    test('a JSON array', () async {
      // It reached `d.toJson()`: a NoSuchMethodError, which `on Exception`
      // does not catch, so Dio failed the request with it.
      final response = await _dio(
        '[1, 2]',
        contentType: Headers.jsonContentType,
      ).get<Object?>('/list');

      expect(response.data, [1, 2]);
    });

    test('a plain-text body', () async {
      // It went through `jsonDecode`: a FormatException, same outcome.
      final response = await _dio(
        'pong',
        contentType: 'text/plain',
      ).get<Object?>('/ping');

      expect(response.data, 'pong');
      expect(lines.join('\n'), contains('pong'));
    });
  });

  group('formatBody', () {
    test('never throws, and never prints the codec', () {
      for (final body in <Object?>[
        null,
        'not json',
        '{"a": 1}',
        [1, 'two'],
        {'when': DateTime(2020)},
        Object(),
        Uint8List(3),
      ]) {
        final text = formatBody(body);
        expect(text, isNot(contains('JsonCodec')), reason: '$body');
      }
    });

    test('an object without toJson prints as itself', () {
      expect(formatBody(Object()), "Instance of 'Object'");
    });

    test('an object with toJson prints its JSON', () {
      expect(jsonDecode(formatBody(_Model())), {'name': 'x'});
    });
  });

  group('secrets are not logged', () {
    test('the password of a login body', () {
      final text = formatBody({
        'email': 'a@b.c',
        'password': 'Secret123',
        'nested': {'refreshToken': 'r'},
      });

      expect(text, isNot(contains('Secret123')));
      expect(text, isNot(contains('"r"')));
      expect(text, contains('a@b.c'));
    });

    test('the same body arriving as a JSON string', () {
      expect(
        formatBody('{"password": "Secret123"}'),
        isNot(contains('Secret123')),
      );
    });

    test('the Authorization header and the response cookie', () async {
      await _dio('{}', contentType: Headers.jsonContentType).post<Object?>(
        '/login',
        data: {'email': 'a@b.c', 'password': 'Secret123'},
        options: Options(headers: {'Authorization': 'Bearer tok'}),
      );

      final log = lines.join('\n');
      expect(log, isNot(contains('Bearer tok')));
      expect(log, isNot(contains('Secret123')));
      expect(log, isNot(contains('abc123')));
      expect(log, contains('Authorization'), reason: 'the name stays');
    });
  });
}

class _Model {
  Map<String, Object?> toJson() => {'name': 'x'};
}
