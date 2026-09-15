import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// `frx new` — the wizard turns answers into the argv of a real command, echoes
/// that line, and runs it.
///
/// It was the one command with no test of its own, because it read
/// `stdin.readLineSync()` directly and every in-process seam went around it.
/// The answers now arrive through the console, so a test is a string.
///
/// The menu is numbered in the order the wizard lists it: 1 substate, 2 page,
/// 3 action, 4 tabs, 5 model, 6 enum, 7 widget, 8 connector, 9 service,
/// 10 retrofit, 11 theme-extension.
void main() {
  late Fixture fx;
  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  test('substate: kind and no build_runner become add-substate -k', () async {
    final r = await runInProcess(
      fx,
      ['new'],
      input: '1\nuser profile\n1\nn\n',
    );

    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout, contains('> frx add-substate user profile -k value'));
    final stateFile = fx.file(
      'business/lib/redux/user_profile/models/user_profile_state.dart',
    );
    expect(
      stateFile.existsSync(),
      isTrue,
      reason: 'the echoed command line is the one that ran',
    );
  });

  test('page: a yes to public becomes --public', () async {
    final r = await runInProcess(fx, ['new'], input: '2\nsettings\ny\nn\n');

    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout, contains('> frx add-page settings --public'));
    expect(
      fx.read('app/lib/navigation/app_router.dart'),
      contains('SettingsRoute'),
    );
  });

  test('enum: a comma list becomes one -v per value', () async {
    final r = await runInProcess(
      fx,
      ['new'],
      input: '6\npriority\nlow, high\n',
    );

    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout, contains('> frx add-enum priority -v low -v high'));
  });

  test('the option name is accepted in place of its number', () async {
    final r = await runInProcess(fx, ['new'], input: 'enum\npriority\nlow\n');

    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout, contains('> frx add-enum priority -v low'));
  });

  test('a name that is not a name is asked again, not passed on', () async {
    final r = await runInProcess(
      fx,
      ['new'],
      input: '6\n1abc\npriority\nlow\n',
    );

    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout, contains('(invalid'));
    expect(r.stdout, contains('> frx add-enum priority -v low'));
  });

  test(
    'the end of input aborts with the usage code and runs nothing',
    () async {
      final r = await runInProcess(fx, ['new'], input: '1\n');

      expect(r.exitCode, 64);
      expect(r.stdout, contains('Aborted.'));
      expect(r.stdout, isNot(contains('> frx')));
    },
  );

  test('--root travels to the command it builds', () async {
    // `runInProcess` appends `--root <fixture>`; the wizard has to hand it on,
    // or the command it runs resolves from the cwd instead.
    final r = await runInProcess(fx, ['new'], input: '6\npriority\nlow\n');

    expect(r.stdout, contains('--root ${fx.root.path}'));
  });
}
