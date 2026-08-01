import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// A waiting action arrives with the reader for the only thing it makes
/// observable.
///
/// The completion boundary applied: frx wires what an artifact *implies* and
/// leaves what is *chosen*. `add-field`'s justification — a field a connector
/// cannot read is half-wired — transfers word for word, and the evidence is in
/// the template, where four of six computed selectors are this idiom by hand,
/// one per waiting action.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  String selectors() => fx.read('business/lib/redux/selectors.dart');

  Future<Ran> addAction(List<String> args) async {
    final r = await runInProcess(fx, ['add-action', ...args]);
    expect(r.exitCode, 0, reason: '${args.join(' ')}\n${r.stderr}');
    return r;
  }

  test('a waiting action adds the substate isWaiting getter', () async {
    await addAction(['save_profile', '-s', 'log_in', '-k', 'waiting']);
    expect(
      selectors(),
      contains(
        'bool get isWaiting => '
        '_state.wait.isWaitingForType<SaveProfileAction>();',
      ),
    );
    expect(
      fx
          .file('business/lib/redux/log_in/actions/save_profile_action.dart')
          .existsSync(),
      isTrue,
    );
  });

  test('the getter lands in the substate own Select block', () async {
    await addAction(['save_profile', '-s', 'log_in', '-k', 'waiting']);
    final src = selectors();
    final block = src.substring(src.indexOf('extension type SelectLogIn'));
    expect(block, contains('isWaiting'));
    // Not in the neighbour's — the getter belongs to the substate whose action
    // it observes.
    final other = src.substring(
      src.indexOf('extension type SelectConnectivity'),
      src.indexOf('extension type SelectLogIn'),
    );
    expect(other, isNot(contains('isWaiting')));
  });

  test('--no-selector skips it, like add-field', () async {
    await addAction([
      'save_profile',
      '-s',
      'log_in',
      '-k',
      'waiting',
      '--no-selector',
    ]);
    expect(selectors(), isNot(contains('isWaiting')));
    expect(
      fx
          .file('business/lib/redux/log_in/actions/save_profile_action.dart')
          .existsSync(),
      isTrue,
      reason: 'the action itself is unaffected by the opt-out',
    );
  });

  test('sync and async kinds are unaffected', () async {
    await addAction(['tap', '-s', 'log_in']);
    await addAction(['fetch', '-s', 'log_in', '-k', 'async']);
    expect(selectors(), isNot(contains('isWaiting')));
  });

  test('a taken isWaiting is left alone and reported', () async {
    // Two waiting actions in one substate. Naming the second getter after its
    // action would make the four already in the template an exception to their
    // own rule, so the collision is handed back to the author instead.
    await addAction(['save_profile', '-s', 'log_in', '-k', 'waiting']);
    final afterFirst = selectors();

    final second = await addAction([
      'refresh_profile',
      '-s',
      'log_in',
      '-k',
      'waiting',
    ]);

    expect(selectors(), afterFirst, reason: 'nothing was overwritten');
    // On stderr, not in the plan's narration: narration is the human report and
    // is silent under `--json`, and the consumer that most needs to hear "the
    // reader was not added" is the agent the machine format exists for.
    expect(second.stderr, contains('isWaiting is taken'));
    expect(
      second.stderr,
      contains('RefreshProfileAction'),
      reason: 'the author is told which action still needs a reader',
    );
    expect(
      fx
          .file('business/lib/redux/log_in/actions/refresh_profile_action.dart')
          .existsSync(),
      isTrue,
    );
  });

  test('a substate outside the facade still gets its action', () async {
    // The action is what was asked for; refusing the whole command over the
    // half it volunteered would be the worse trade.
    Directory(fx.path('business/lib/redux/stray/actions'))
      ..createSync(recursive: true);
    final r = await addAction(['save', '-s', 'stray', '-k', 'waiting']);
    expect(r.stderr, contains('SelectStray is not wired'));
    expect(
      fx.file('business/lib/redux/stray/actions/save_action.dart').existsSync(),
      isTrue,
    );
  });

  test('the four selectors already in the live template are untouched', () {
    // The work adds a default; it does not rewrite what is there. Read from the
    // real monorepo, because that is where the four are.
    final live = File('../business/lib/redux/selectors.dart');
    if (!live.existsSync()) return;
    final src = live.readAsStringSync();
    expect(
      RegExp(
        r'bool get isWaiting => _state\.wait\.isWaitingForType<\w+Action>\(\);',
      ).allMatches(src).length,
      4,
    );
  });

  test('a --json consumer hears about a skipped reader too', () async {
    // The whole point of routing the note to stderr: an agent that only reads the
    // changeset would otherwise see the action created and never learn that the
    // reader it implies was left out.
    await addAction(['save_profile', '-s', 'log_in', '-k', 'waiting']);
    final second = await runInProcess(fx, [
      'add-action',
      'refresh_profile',
      '-s',
      'log_in',
      '-k',
      'waiting',
      '--json',
    ]);
    expect(second.exitCode, 0);
    expect(second.stderr, contains('isWaiting is taken'));
    expect(
      const LineSplitter().convert(second.stdout).where((l) => l.isNotEmpty),
      hasLength(1),
      reason: 'stdout still carries only the changeset',
    );
  });

  test('the dry run shows the selector edit without making it', () async {
    final r = await runInProcess(fx, [
      'add-action',
      'save_profile',
      '-s',
      'log_in',
      '-k',
      'waiting',
      '--dry-run',
    ]);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('SelectLogIn.isWaiting'));
    expect(selectors(), isNot(contains('isWaiting')));
  });
}
