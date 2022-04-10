import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:utils/api/auth_service.dart';

const baseUrl = 'http://localhost:8000';

ChopperClient buildClient([
  http.Client? httpClient,
  ErrorConverter? errorConverter,
]) =>
    ChopperClient(
      baseUrl: baseUrl,
      services: [
        // the generated service
        AuthService.create(),
      ],
      client: httpClient,
      errorConverter: errorConverter,
      converter: const JsonConverter(),
    );
void main() {
  group('Auth service', () {
    test('Login', () async {
      const password = 'password';
      const email = 'email@example.com';
      const result = 'session_token';
      final body = <String, dynamic>{
        'email': email,
        'password': password,
      };

      final httpClient = MockClient((request) async {
        expect(
          request.url.toString(),
          equals('$baseUrl/login'),
        );

        final convertedBody = json.encode(body);
        expect(request.method, equals('POST'));
        expect(request.body, equals(convertedBody));

        return http.Response(result, 200);
      });

      final chopper = buildClient(httpClient);
      final service = chopper.getService<AuthService>();
      final response = await service.logIn(body: body);

      expect(response.body, equals(result));
      expect(response.statusCode, equals(200));

      httpClient.close();
    });
  });
}
