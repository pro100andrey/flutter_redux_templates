import 'package:test/test.dart';

import 'support/fixture.dart';

/// `frx remove --kind selector` — the other half of `add-selector`.
///
/// The asymmetry this closes: `add-selector` writes a computed getter into the
/// facade and nothing took one out, while `selectors.dart` sits under the
/// placement guard — so the only way out was a hand edit to a file frx
/// complains about being hand-edited. The splice itself already existed; the
/// field path has used it since `--kind field` shipped, to remove the getter it
/// wrote beside a field.
void main() {
  late Fixture fx;
  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  String selectors() => fx.read('business/lib/redux/selectors.dart');

  test('removes the getter, addressed the way graph prints it', () async {
    final res = await runFrx(fx, [
      'remove',
      'SelectLogIn.email',
      '--kind',
      'selector',
      '--apply',
      '--no-format',
    ]);

    expect(res.exitCode, 0, reason: '${res.stderr}');
    expect(selectors(), isNot(contains('get email')));
    expect(
      selectors(),
      contains('SelectConnectivity'),
      reason: 'the rest of the facade is untouched',
    );
  });

  test('takes the bare name with --state', () async {
    final res = await runFrx(fx, [
      'remove',
      'email',
      '--kind',
      'selector',
      '--state',
      'log_in',
      '--apply',
      '--no-format',
    ]);

    expect(res.exitCode, 0, reason: '${res.stderr}');
    expect(selectors(), isNot(contains('get email')));
  });

  test('previews without --apply', () async {
    final before = selectors();
    final res = await runFrx(fx, [
      'remove',
      'SelectLogIn.email',
      '--kind',
      'selector',
    ]);

    expect(res.exitCode, 0, reason: '${res.stderr}');
    expect(selectors(), before);
    expect(res.stdout, contains('SelectLogIn.email'));
  });

  test('refuses while another getter on the facade reads it', () async {
    // The same refusal the field path makes, for the same reason: the reader is
    // in the file being spliced, and a selector body is the author's to
    // rewrite. Writing the splice anyway would leave a file that cannot
    // compile and report success.
    fx
        .file('business/lib/redux/selectors.dart')
        .writeAsStringSync(
          selectors().replaceFirst(
            'String? get email => _state.logIn.email;',
            'String? get email => _state.logIn.email;\n'
                '  bool get hasEmail => email != null;',
          ),
        );

    final res = await runFrx(fx, [
      'remove',
      'SelectLogIn.email',
      '--kind',
      'selector',
      '--apply',
    ]);

    expect(res.exitCode, isNot(0));
    expect(res.stderr, contains('SelectLogIn.hasEmail'));
    expect(selectors(), contains('get email'));
  });

  test('refuses a getter the facade does not declare', () async {
    final res = await runFrx(fx, [
      'remove',
      'SelectLogIn.nope',
      '--kind',
      'selector',
      '--apply',
    ]);

    expect(res.exitCode, isNot(0));
    expect(res.stderr, contains('has no "nope" getter'));
  });
}
