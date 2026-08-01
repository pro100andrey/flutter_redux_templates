import 'dart:convert';

import 'package:test/test.dart';

import 'support/fixture.dart';

/// `frx which` resolves an identifier back to its artifact — the authoritative
/// token → artifact map the editor rename relies on.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  Future<Map<String, dynamic>> which(String token) async {
    final res = await runFrx(fx, ['which', token, '--json']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    return jsonDecode(res.stdout as String) as Map<String, dynamic>;
  }

  test(
    'a state class resolves to its substate with the State suffix',
    () async {
      expect(await which('LogInState'), {
        'kind': 'substate',
        'name': 'log_in',
        'suffix': 'State',
        'prefix': null,
      });
    },
  );

  test(
    'a Select<Pascal> resolves to its substate with the Select prefix',
    () async {
      expect(await which('SelectConnectivity'), {
        'kind': 'substate',
        'name': 'connectivity',
        'suffix': null,
        'prefix': 'Select',
      });
    },
  );

  test('a bare field resolves to its substate (no suffix/prefix)', () async {
    expect(await which('logIn'), {
      'kind': 'substate',
      'name': 'log_in',
      'suffix': null,
      'prefix': null,
    });
  });

  test('a route class resolves to its page with the Route suffix', () async {
    expect(await which('HomeRoute'), {
      'kind': 'page',
      'name': 'home',
      'suffix': 'Route',
      'prefix': null,
    });
  });

  test(
    'a connector class resolves to its page with the PageConnector suffix',
    () async {
      expect(await which('LogInPageConnector'), {
        'kind': 'page',
        'name': 'log_in',
        'suffix': 'PageConnector',
        'prefix': null,
      });
    },
  );

  test('an unknown identifier resolves to kind null', () async {
    expect(await which('TotallyUnknownThing'), {'kind': null});
  });
}
