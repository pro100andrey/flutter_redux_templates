import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `frx remove --kind field` — the inverse of `add-field`, and the way out of
/// a field the scaffolder wrote.
///
/// The hole this closes was measured in a build against another repository: a
/// slice made with the default kind arrives with `value`, the feature never
/// used it, and nothing could take it out. `remove` knew actions and not
/// fields, and the state file's own guard refuses the hand edit — correctly,
/// since a field there carries wiring. The field shipped unused.
///
/// So the property under test is the whole set, the same one the file kinds
/// are held to: the factory parameter, the getter on the facade, and the
/// setter action that copies it.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  String state([String substate = 'log_in']) =>
      fx.read('business/lib/redux/$substate/models/${substate}_state.dart');
  String selectors() => fx.read('business/lib/redux/selectors.dart');

  Future<void> ok(List<String> args) async {
    final res = await runFrx(fx, args);
    expect(res.exitCode, 0, reason: '${args.join(' ')}\n${res.stderr}');
  }

  /// Every applying test here passes `--no-format`, so nothing downstream
  /// normalises what the splices wrote — which is the point. `dart format`
  /// failing is a *warning* the write path swallows (build_step.dart), so a
  /// command that produced unparseable Dart still exits 0, and a suite that only
  /// reads the text with `contains` cannot tell the two apart.
  void expectParses(String relative) {
    final source = fx.read(relative);
    expect(
      () => parseString(content: source),
      returnsNormally,
      reason: 'frx wrote Dart that does not parse:\n$source',
    );
  }

  test('the field leaves the state factory', () async {
    await ok([
      'remove',
      'value',
      '--kind',
      'field',
      '--state',
      'log_in',
      '--apply',
      '--no-format',
    ]);
    expect(state(), isNot(contains('value')));
    // The fixture's only field: an empty named group (`({})`) does not parse,
    // so the braces go with it.
    expect(state(), contains('const factory LogInState() = _LogInState;'));
    expectParses('business/lib/redux/log_in/models/log_in_state.dart');
  });

  test('the last field of a named group takes only the group', () async {
    // A factory with positional parameters *and* a named group: the named one
    // is the field, and counting the whole parameter list instead of the group
    // wrote `(int id, {})` — which does not parse, into the one file the guard
    // will not let anybody repair by hand.
    fx.file('business/lib/redux/checkout/models/checkout_state.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:freezed_annotation/freezed_annotation.dart';

part 'checkout_state.freezed.dart';

@freezed
abstract class CheckoutState with _\$CheckoutState {
  const factory CheckoutState(int id, {String? fallback}) = _CheckoutState;
}
''');

    await ok([
      'remove',
      'fallback',
      '--kind',
      'field',
      '--state',
      'checkout',
      '--apply',
      '--no-format',
    ]);
    final source = fx.read(
      'business/lib/redux/checkout/models/checkout_state.dart',
    );
    expect(source, contains('const factory CheckoutState(int id)'));
    expect(source, isNot(contains('{}')));
    expectParses('business/lib/redux/checkout/models/checkout_state.dart');
  });

  test('a field round-trips through add-field', () async {
    await ok(['add-field', 'log_in', 'nickname:String?', '--no-format']);
    expect(state(), contains('String? nickname'));
    expect(selectors(), contains('get nickname'));

    await ok([
      'remove',
      'nickname',
      '--kind',
      'field',
      '--apply',
      '--no-format',
    ]);
    expect(state(), isNot(contains('nickname')));
    expect(selectors(), isNot(contains('nickname')));
    // The neighbour it was spliced beside stays, with a parseable factory.
    expect(state(), contains('const factory LogInState({String? value})'));
    expectParses('business/lib/redux/log_in/models/log_in_state.dart');
    expectParses('business/lib/redux/selectors.dart');
  });

  test('without --apply nothing is written', () async {
    final before = state();
    final res = await runFrx(fx, [
      'remove',
      'value',
      '--kind',
      'field',
      '--state',
      'log_in',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(res.stdout, contains('--apply'));
    expect(state(), before);
  });

  test('the setter action goes with the field', () async {
    await ok([
      'add-field',
      'log_in',
      'nickname:String?',
      '--action',
      '--no-format',
    ]);
    final setter = fx.file(
      'business/lib/redux/log_in/actions/set_nickname_action.dart',
    );
    expect(setter.existsSync(), isTrue);

    await ok([
      'remove',
      'nickname',
      '--kind',
      'field',
      '--apply',
      '--no-format',
    ]);
    expect(
      setter.existsSync(),
      isFalse,
      reason: 'it copyWiths a field that is gone — it cannot compile',
    );
  });

  test('one field name under two substates is refused, not guessed', () async {
    // Every slice `add-substate` makes with its default kind carries a `value`,
    // so this is the common case rather than the corner one — and under
    // `--apply` picking one is not recoverable.
    final res = await runFrx(fx, [
      'remove',
      'value',
      '--kind',
      'field',
      '--apply',
    ]);
    expect(res.exitCode, 64, reason: res.stderr.toString());
    expect(res.stderr.toString(), contains('--state'));
    expect(state(), contains('value'));
    expect(state('connectivity'), contains('value'));
  });

  test('--state takes one and leaves the other', () async {
    await ok([
      'remove',
      'value',
      '--kind',
      'field',
      '--state',
      'connectivity',
      '--apply',
      '--no-format',
    ]);
    expect(state('connectivity'), isNot(contains('value')));
    expect(state(), contains('String? value'));
  });

  test('the last user of an import takes the import with it', () async {
    await ok([
      'add-field',
      'log_in',
      'tags:IList<String>',
      '--default',
      'IListConst([])',
      '--no-format',
    ]);
    expect(state(), contains('fast_immutable_collections'));
    expect(selectors(), contains('fast_immutable_collections'));

    await ok(['remove', 'tags', '--kind', 'field', '--apply', '--no-format']);
    expect(
      state(),
      isNot(contains('fast_immutable_collections')),
      reason: 'an import nothing names anymore trips unused_import',
    );
    expect(selectors(), isNot(contains('fast_immutable_collections')));
  });

  test('an import another field still needs stays', () async {
    for (final spec in const ['tags:IList<String>', 'ids:IList<int>']) {
      await ok([
        'add-field',
        'log_in',
        spec,
        '--default',
        'IListConst([])',
        '--no-format',
      ]);
    }

    await ok(['remove', 'tags', '--kind', 'field', '--apply', '--no-format']);
    expect(state(), contains('IList<int> ids'));
    expect(
      state(),
      contains('fast_immutable_collections'),
      reason: 'ids still needs it',
    );
    expect(selectors(), contains('fast_immutable_collections'));
  });

  test('the accessors derived from the getter go with it', () async {
    // `add-substate -k table` writes two members out of one fact: the `table`
    // getter and a `byId` that indexes it. A removal that took only the getter
    // would leave a method reading a collection that is gone.
    await ok(['add-substate', 'Tasks', '--kind', 'table', '--no-format']);
    expect(selectors(), contains('byId'));

    await ok([
      'remove',
      'table',
      '--kind',
      'field',
      '--state',
      'tasks',
      '--apply',
      '--no-format',
    ]);
    // On a word boundary: `fast_immutable_collections` carries the substring.
    expect(state('tasks'), isNot(matches(RegExp(r'\btable\b'))));
    expect(selectors(), isNot(contains('byId')));
    // Its neighbours in the same block are untouched — including `view`, whose
    // body mentions the table in a doc comment but does not index it.
    expect(selectors(), contains('get isWaiting'));
    expect(selectors(), contains('IList<int> get view'));
  });

  test('a field no substate declares is refused', () async {
    final res = await runFrx(fx, [
      'remove',
      'nope',
      '--kind',
      'field',
      '--apply',
    ]);
    expect(res.exitCode, 70);
    expect(res.stderr.toString(), contains('nope'));
  });

  test('a name the substate does not carry is refused', () async {
    final res = await runFrx(fx, [
      'remove',
      'nickname',
      '--kind',
      'field',
      '--state',
      'log_in',
      '--apply',
    ]);
    expect(res.exitCode, 70);
    expect(res.stderr.toString(), contains('LogInState'));
    expect(state(), contains('value'));
  });

  test('a selector still reading the getter blocks the removal', () async {
    // The shape this repository's own template ships:
    //
    //   String? get token => _state.session.token;
    //   bool get isAvailable => token != null;
    //
    // The facade is the one file of this architecture the guard *allows* hand
    // edits to, so a sibling reading the getter is ordinary. Deleting `token`
    // and reporting success left `isAvailable` undefined — and the template's
    // `SelectComposites.canEnterApp` reads that, so `business` stopped
    // compiling, `build_runner` included.
    await ok(['add-field', 'log_in', 'token:String?', '--no-format']);
    final path = 'business/lib/redux/selectors.dart';
    fx
        .file(path)
        .writeAsStringSync(
          fx
              .read(path)
              .replaceFirst(
                'String? get token => _state.logIn.token;',
                'String? get token => _state.logIn.token;\n'
                    '  bool get isAvailable => token != null;',
              ),
        );

    final res = await runFrx(fx, [
      'remove',
      'token',
      '--kind',
      'field',
      '--apply',
      '--no-format',
    ]);
    expect(res.exitCode, 70, reason: res.stdout.toString());
    expect(res.stderr.toString(), contains('SelectLogIn.isAvailable'));
    expect(state(), contains('token'), reason: 'nothing was written');
    expect(fx.read(path), contains('isAvailable'));
  });

  test('a computed getter on the state class blocks the removal', () async {
    // Same rule one file over, and the sharper half: a state file cannot be
    // repaired by hand at all — the guard refuses Write, Edit and the shell —
    // so writing one that does not compile leaves its owner with no way out.
    fx.file('business/lib/redux/session/models/session_state.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_state.freezed.dart';

@freezed
abstract class SessionState with _\$SessionState {
  const SessionState._();

  const factory SessionState({String? token}) = _SessionState;

  bool get isAuthenticated => token != null;
}
''');

    final res = await runFrx(fx, [
      'remove',
      'token',
      '--kind',
      'field',
      '--state',
      'session',
      '--apply',
      '--no-format',
    ]);
    expect(res.exitCode, 70, reason: res.stdout.toString());
    expect(res.stderr.toString(), contains('SessionState.isAuthenticated'));
    expect(
      fx.read('business/lib/redux/session/models/session_state.dart'),
      contains('String? token'),
    );
  });

  test('a method indexing another slice s collection survives', () async {
    await ok(['add-substate', 'Tasks', '--kind', 'table', '--no-format']);
    await ok(['add-substate', 'Labels', '--kind', 'table', '--no-format']);
    // Hand-written into SelectTasks, reading SelectLabels' collection. It
    // indexes something *called* `table`, and it is not this getter's accessor:
    // deleting it would be silent loss of hand-written code, reported as
    // intended.
    final path = 'business/lib/redux/selectors.dart';
    fx
        .file(path)
        .writeAsStringSync(
          fx
              .read(path)
              .replaceFirst(
                'extension type SelectTasks(AppState _state) {',
                'extension type SelectTasks(AppState _state) {\n'
                    '  Object? labelFor(int id) => _state.labels.table[id];',
              ),
        );

    await ok([
      'remove',
      'table',
      '--kind',
      'field',
      '--state',
      'tasks',
      '--apply',
      '--no-format',
    ]);
    expect(selectors(), contains('labelFor'));
    // SelectTasks' own accessor goes; SelectLabels' identically named one does
    // not, because it indexes a getter this removal never touched.
    expect('Object byId'.allMatches(selectors()).length, 1);
    expect(selectors(), contains('IMap<int, Object> get table'));
    expectParses(path);
  });

  test('a union case keeps the import its own file supplies', () async {
    // `add-model -c` writes the union *and its cases* into one file, so the
    // import is needed by names the file is not called after. A probe that only
    // knew `Result` pruned it out from under `ResultSuccess`.
    await ok(['add-model', 'Result', '-c', 'loading', '-c', 'success']);
    await ok(['add-field', 'log_in', 'outcome:Result?', '--no-format']);
    await ok(['add-field', 'log_in', 'last:ResultSuccess?', '--no-format']);

    await ok([
      'remove',
      'outcome',
      '--kind',
      'field',
      '--apply',
      '--no-format',
    ]);
    expect(state(), contains('ResultSuccess? last'));
    expect(
      state(),
      contains('package:models/result.dart'),
      reason: 'ResultSuccess is declared in it',
    );
    expect(selectors(), contains('package:models/result.dart'));
  });

  test('an import a wider collection type still needs stays', () async {
    // The rule that *adds* the import ends in `\\b`, so it does not match
    // `IMapOfSets` — a real export of the same package. Reused as the rule that
    // keeps it, that trailing boundary prunes the import out from under a live
    // type. Erring wide costs a lint; erring narrow costs the build.
    await ok([
      'add-field',
      'log_in',
      'tags:IList<String>',
      '--default',
      'IListConst([])',
      '--no-format',
    ]);
    await ok([
      'add-selector',
      'log_in',
      'groups',
      '--type',
      'IMapOfSets<int, String>',
      '--expr',
      'const IMapOfSets.empty()',
      '--no-format',
    ]);

    await ok(['remove', 'tags', '--kind', 'field', '--apply', '--no-format']);
    expect(selectors(), contains('IMapOfSets'));
    expect(
      selectors(),
      contains('fast_immutable_collections'),
      reason: 'IMapOfSets comes from it too',
    );
  });

  test('a --state that is not a name is a usage error, not a crash', () async {
    final res = await runFrx(fx, [
      'remove',
      'value',
      '--kind',
      'field',
      '--state',
      '_shared',
      '--apply',
    ]);
    expect(res.exitCode, 64, reason: res.stderr.toString());
    expect(res.stderr.toString(), contains('--state'));
  });

  test(
    'an odd folder under redux/ does not crash an unrelated remove',
    () async {
      // The field search runs on the failure path of *every* remove, so a folder
      // name `Casing` will not read — `_shared/`, `2fa/`, `__gen/` — turned a
      // plain typo into an unhandled FormatException and exit 255.
      fx.file('business/lib/redux/_shared/models/_shared_state.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// not a state class\n');

      final res = await runFrx(fx, ['remove', 'Nope', '--apply']);
      expect(res.exitCode, 70, reason: res.stderr.toString());
      expect(res.stderr.toString(), isNot(contains('Unhandled exception')));
    },
  );

  test('a name that is both a field and a model is refused', () async {
    // `remove tags` resolved to the model and never mentioned the field. An
    // ambiguity resolved by a rule is still an ambiguity, and under `--apply`
    // it is unrecoverable.
    await ok(['add-field', 'log_in', 'tags:String?', '--no-format']);
    await ok(['add-model', 'Tags', '--no-format']);

    final res = await runFrx(fx, ['remove', 'tags', '--apply']);
    expect(res.exitCode, 64, reason: res.stderr.toString());
    expect(res.stderr.toString(), contains('field'));
    expect(res.stderr.toString(), contains('model'));
    expect(fx.file('models/lib/tags.dart').existsSync(), isTrue);
    expect(state(), contains('tags'));
  });

  test('the slice actions that still assign it are named, not deleted', () async {
    // `add_tasks_action.dart` is the slice's, not the field's — deleting it is
    // not this command's call. But it assigns the field, so it stops compiling,
    // and "run the audit" does not say which file.
    await ok(['add-substate', 'Tasks', '--kind', 'table', '--no-format']);
    final adder = fx.file(
      'business/lib/redux/tasks/actions/add_tasks_action.dart',
    );
    expect(adder.readAsStringSync(), contains('table'));

    final res = await runFrx(fx, [
      'remove',
      'table',
      '--kind',
      'field',
      '--state',
      'tasks',
      '--apply',
      '--no-format',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(adder.existsSync(), isTrue);
    expect(res.stdout.toString(), contains('add_tasks_action.dart'));
    expect(res.stdout.toString(), contains('will not compile'));
  });

  test('a state file that does not parse is refused, not spliced', () async {
    fx
        .file('business/lib/redux/log_in/models/log_in_state.dart')
        .writeAsStringSync('''
import 'package:freezed_annotation/freezed_annotation.dart';

@freezed
abstract class LogInState with _\$LogInState {
  const factory LogInState({String? value}) = _LogInState
}
''');

    final res = await runFrx(fx, [
      'remove',
      'value',
      '--kind',
      'field',
      '--state',
      'log_in',
      '--apply',
    ]);
    expect(res.exitCode, 70, reason: res.stdout.toString());
    expect(res.stderr.toString(), contains('does not parse'));
  });

  test('a bare remove of a field name names the command that does it', () async {
    // Auto-detection deliberately does not reach fields: a field is spelled
    // like a substate's own field, and detecting one would put `--kind page`
    // between the user and a page whose name a field happens to share. What
    // carries the discoverability instead is this message — without it the next
    // move is the hand edit the guard refuses.
    await ok(['add-field', 'log_in', 'nickname:String?', '--no-format']);

    final res = await runFrx(fx, ['remove', 'nickname', '--apply']);
    expect(res.exitCode, 70);
    expect(res.stderr.toString(), contains('--kind field'));
    expect(res.stderr.toString(), contains('log_in'));
  });
}
