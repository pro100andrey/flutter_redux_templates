import 'dart:io';

import 'package:test/test.dart';
import 'package:tools/src/config/frx_config.dart';

import 'support/fixture.dart';

void main() {
  group('FrxConfig.load', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('frx_cfg_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads the recognized keys', () {
      File('${dir.path}/.frxrc').writeAsStringSync(
        '{"buildRunner": true, "format": false, "substateKind": "table"}',
      );
      final c = FrxConfig.load(startDir: dir.path);
      expect(c.buildRunner, isTrue);
      expect(c.format, isFalse);
      expect(c.substateKind, 'table');
    });

    test('a missing file is an empty config', () {
      expect(FrxConfig.load(startDir: dir.path).isEmpty, isTrue);
    });

    test('a malformed file is ignored (empty), never throws', () {
      File('${dir.path}/.frxrc').writeAsStringSync('{ not json');
      expect(FrxConfig.load(startDir: dir.path).isEmpty, isTrue);
    });
  });

  group('FrxConfig.applyTo', () {
    const options = {'build-runner', 'format', 'kind', 'root'};

    test('injects a flag the user did not set', () {
      const c = FrxConfig(buildRunner: true);
      expect(
        c.applyTo(['add-substate', 'x'], 'add-substate', options),
        contains('--build-runner'),
      );
    });

    test('an explicit flag always wins over the config', () {
      const c = FrxConfig(buildRunner: true);
      // User passed the short -b already: no duplicate injected.
      final out = c.applyTo(
        ['add-substate', 'x', '-b'],
        'add-substate',
        options,
      );
      expect(out.where((a) => a == '--build-runner'), isEmpty);
      // User passed --no-format: config's format:false must not add another.
      const c2 = FrxConfig(format: false);
      final out2 = c2.applyTo(
        ['add-substate', 'x', '--no-format'],
        'add-substate',
        options,
      );
      expect(out2.where((a) => a == '--no-format'), hasLength(1));
    });

    test('substateKind only defaults add-substate, not add-action', () {
      const c = FrxConfig(substateKind: 'table');
      expect(
        c.applyTo(['add-substate', 'x'], 'add-substate', options),
        containsAllInOrder(['--kind', 'table']),
      );
      // add-action also has a `kind` option, but with different values — leave it.
      expect(
        c.applyTo(['add-action', 'x'], 'add-action', options),
        isNot(contains('--kind')),
      );
    });

    test('skips flags the command does not accept', () {
      const c = FrxConfig(buildRunner: true);
      // A command without build-runner (e.g. add-widget) gets nothing injected.
      expect(
        c.applyTo(['add-widget', 'x'], 'add-widget', {'format', 'root'}),
        isNot(contains('--build-runner')),
      );
    });
  });

  group('.frxrc end to end', () {
    late Fixture fx;
    setUp(() => fx = Fixture.create());
    tearDown(() => fx.dispose());

    test('substateKind is applied, and an explicit --kind wins', () async {
      fx.file('.frxrc').writeAsStringSync('{"substateKind": "search"}');

      final def = await runFrx(fx, ['add-substate', 'demo', '--dry-run']);
      expect(def.exitCode, 0, reason: def.stderr.toString());
      expect(def.stdout, contains('kind: search'));

      final override = await runFrx(fx, [
        'add-substate',
        'demo',
        '--kind',
        'value',
        '--dry-run',
      ]);
      expect(override.exitCode, 0, reason: override.stderr.toString());
      expect(override.stdout, contains('kind: value'));
    });
  });
}
