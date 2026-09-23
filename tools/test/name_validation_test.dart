import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';
import 'package:tools/src/scaffold/widget_scaffold.dart';
import 'package:tools/src/util/casing.dart';
import 'package:tools/src/util/console.dart';
import 'package:tools/src/util/dart_names.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// Names the scaffolders are handed that Dart, or the context, will not take.
///
/// Each of these used to be written: into a file that did not parse, over a
/// member the class already had, or — for `add-substate class` — into the
/// formatter, which died with a stack trace. A usage error before anything is
/// written is the whole of the fix, so that is what each asserts: the exit
/// code, the reason, and that the tree did not change.
void main() {
  group('DartNames', () {
    test('a reserved word, a built-in, a taken member, a plain name', () {
      expect(DartNames.problem('switch'), contains('reserved word'));
      expect(DartNames.problem('required'), contains('built-in'));
      expect(
        DartNames.problem('key', taken: DartNames.widgetMembers),
        contains('Widget.key'),
      );
      expect(DartNames.problem('title'), isNull);
    });

    test('both spellings are asked — the field and the class', () {
      expect(DartNames.problemWith(Casing.parse('class')), isNotNull);
      expect(DartNames.problemWith(Casing.parse('function')), isNotNull);
      expect(DartNames.problemWith(Casing.parse('task_list')), isNull);
    });
  });

  group('scaffolders refuse', () {
    late Fixture fx;

    setUp(() => fx = Fixture.create());
    tearDown(() => fx.dispose());

    /// Every file under the fixture, with its contents — what "nothing was
    /// written" means.
    Map<String, String> tree() => {
      for (final f in fx.root.listSync(recursive: true).whereType<File>())
        p.relative(f.path, from: fx.root.path): f.readAsStringSync(),
    };

    Future<void> refused(
      List<String> args, {
      required Object reason,
      int code = 64,
    }) async {
      final before = tree();
      final res = await runInProcess(fx, args);
      expect(res.exitCode, code, reason: '${args.join(' ')}\n${res.stdout}');
      expect(res.stderr, reason);
      expect(tree(), before, reason: '${args.join(' ')} wrote something');
    }

    test('a reserved word as a substate', () async {
      await refused(['add-substate', 'class'], reason: contains('reserved'));
    });

    test('a reserved word or a freezed member as a field', () async {
      await refused([
        'add-field',
        'log_in',
        'switch:bool?',
      ], reason: contains('reserved'));
      await refused([
        'add-field',
        'log_in',
        'copyWith:bool?',
      ], reason: contains('copyWith'));
    });

    test('a keyword, or a member every enum has, as a value', () async {
      await refused([
        'add-enum',
        'status',
        '-v',
        'active',
        '-v',
        'default',
      ], reason: contains('reserved'));
      await refused([
        'add-enum',
        'mode',
        '-v',
        'values',
      ], reason: contains('values'));
    });

    test("a page parameter spelled like the widget's key", () async {
      await refused([
        'add-page',
        'item',
        '-p',
        'key:String',
      ], reason: contains('Widget.key'));
    });

    test('a widget named after a class its own body uses', () async {
      await refused([
        'add-widget',
        'text',
        '--dir',
        'cards',
      ], reason: contains('`Text`'));
      await refused([
        'add-widget',
        'padding',
        '--dir',
        'cards',
        '-k',
        'container',
      ], reason: contains('`Padding`'));
      expect(
        WidgetScaffold.referencedClasses(WidgetKind.view),
        containsAll(['Text', 'Widget', 'Padding']),
      );
    });

    test("the Redux layer's shared folder is not a substate, even with "
        '--force', () async {
      // `--force` deleted the folder the base `Action` lives in.
      fx.file('business/lib/redux/common/action.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('abstract class AppAction {}\n');
      for (final args in [
        ['add-substate', 'common'],
        ['add-substate', 'common', '--force'],
      ]) {
        await refused(
          args,
          code: 70,
          reason: allOf(contains('shared folder'), isNot(contains('--force'))),
        );
      }
    });

    test('a folder of that name that holds no state is not replaced', () async {
      fx.file('business/lib/redux/legacy/thing.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class Thing {}\n');
      await refused(
        ['add-substate', 'legacy', '--force'],
        code: 70,
        reason: allOf(contains('not a substate'), isNot(contains('--force'))),
      );
    });

    test('a field AppState has that is not a substate', () async {
      // `wait` is async_redux's; the scaffold said "wiring skipped" and wrote a
      // `SelectWait` over `Wait` anyway.
      await refused(
        ['add-substate', 'wait'],
        code: 70,
        reason: contains('"wait" (Wait)'),
      );
    });

    test('a name whose state class is AppState itself', () async {
      await refused(
        ['add-substate', 'app'],
        code: 70,
        reason: contains('AppState is declared'),
      );
    });
  });

  group('create refuses a project name that breaks the workspace', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('frx_create_name_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<({int code, String err})> create(String name) async {
      final captured = CapturedConsole();
      final code = await withConsole(
        captured,
        () => FrxRunner().runFrx([
          'create',
          name,
          '--target',
          p.join(tmp.path, name),
          '--dry-run',
        ]),
      );
      return (code: code, err: captured.errors);
    }

    test('a member, a dependency, a keyword', () async {
      for (final (name, why) in [
        ('business', 'workspace members need unique names'),
        ('async_redux', 'cannot depend on itself'),
        ('class', 'reserved word'),
        ('int', 'Java keyword'),
      ]) {
        final r = await create(name);
        expect(r.code, 64, reason: name);
        expect(r.err, contains(why), reason: name);
      }
      expect((await create('my_shop')).code, 0);
    });
  });
}
