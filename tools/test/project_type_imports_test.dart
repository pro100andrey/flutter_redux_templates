import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/ast/source_index.dart';
import 'package:tools/src/scaffold/type_imports.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

/// What a generated file has to import to name a type this *project* declares —
/// across every package `business` depends on, not just `models`.
///
/// The hole these cover: the resolver used to join `<root>/models/lib/<snake>.dart`
/// and stop, so `add-field boot 'digest:MemoryDigest?'` wrote a field into
/// `boot_state.dart` and a getter onto `selectors.dart` with nothing importing
/// the type — two files that do not compile, and neither of them one a hand edit
/// is allowed to fix.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('frx_imports_'));
  tearDown(() => root.deleteSync(recursive: true));

  void put(String relative, String content) {
    File(p.join(root.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// A `business` that declares [deps] as path dependencies.
  void business(Map<String, String> deps) {
    final entries = deps.entries
        .map((e) => '  ${e.key}:\n    path: ${e.value}\n')
        .join();
    put('business/pubspec.yaml', 'name: business\n\ndependencies:\n$entries');
    put('business/lib/redux/app_state.dart', '// app state\n');
  }

  List<String> importsFor(String type) => inSourceIndex(
    () => ProjectTypeImports.forAll(FrxWorkspace(root), [type]),
  );

  group('a package with a barrel', () {
    setUp(() {
      business({'tm_memory': '../packages/tm_memory'});
      put('packages/tm_memory/pubspec.yaml', 'name: tm_memory\n');
      put('packages/tm_memory/lib/tm_memory.dart', '''
export 'src/application/digest.dart';
''');
      put('packages/tm_memory/lib/src/application/digest.dart', '''
class MemoryDigest {}
''');
    });

    test('resolves through the entry point that exports the declaration', () {
      expect(importsFor('MemoryDigest?'), ['package:tm_memory/tm_memory.dart']);
    });

    test('never names the private file that declares it', () {
      // `package:tm_memory/src/application/digest.dart` is importable in the
      // sense that pub will not stop you, and wrong in every other sense.
      expect(importsFor('MemoryDigest'), isNot(contains(contains('/src/'))));
    });

    test('follows a chain of re-exports', () {
      put('packages/tm_memory/lib/tm_memory.dart', "export 'src/all.dart';\n");
      put('packages/tm_memory/lib/src/all.dart', "export 'application/digest.dart';\n");
      expect(importsFor('MemoryDigest'), ['package:tm_memory/tm_memory.dart']);
    });

    test('a declaration nothing exports resolves to nothing', () {
      // Reachable on disk, unreachable by import. Answering with the private
      // path would be the one thing this module promises never to do.
      put('packages/tm_memory/lib/src/application/secret.dart', 'class Hidden {}\n');
      expect(importsFor('Hidden'), isEmpty);
    });

    test('a package that is not a dependency is not searched', () {
      business({});
      expect(importsFor('MemoryDigest'), isEmpty);
    });

    group('and a combinator on the export', () {
      // `export 'src/sqlite_event_store.dart' show SqliteEventStore` is a real
      // barrel in a real dependency here, and it declares two classes. Ignoring
      // the combinator answers with an import that resolves and does not supply
      // the name — the one failure this module promises it cannot have.
      setUp(() {
        put('packages/tm_memory/lib/src/application/digest.dart', '''
class MemoryDigest {}
class MemoryDigestInternals {}
''');
      });

      test('show admits the name it lists', () {
        put('packages/tm_memory/lib/tm_memory.dart',
            "export 'src/application/digest.dart' show MemoryDigest;\n");
        expect(importsFor('MemoryDigest'), [
          'package:tm_memory/tm_memory.dart',
        ]);
      });

      test('show excludes the sibling it does not', () {
        put('packages/tm_memory/lib/tm_memory.dart',
            "export 'src/application/digest.dart' show MemoryDigest;\n");
        expect(importsFor('MemoryDigestInternals'), isEmpty);
      });

      test('hide excludes the name it lists', () {
        put('packages/tm_memory/lib/tm_memory.dart',
            "export 'src/application/digest.dart' hide MemoryDigest;\n");
        expect(importsFor('MemoryDigest'), isEmpty);
        expect(importsFor('MemoryDigestInternals'), [
          'package:tm_memory/tm_memory.dart',
        ]);
      });

      test('show of a union admits its cases', () {
        // `ResultSuccess` is not a name a combinator can list — it is a
        // constructor redirect on `Result`, and `show Result` carries it.
        put('packages/tm_memory/lib/tm_memory.dart',
            "export 'src/application/result.dart' show Result;\n");
        put('packages/tm_memory/lib/src/application/result.dart', '''
sealed class Result with _\$Result {
  const factory Result.success() = ResultSuccess;
}
''');
        expect(importsFor('ResultSuccess'), [
          'package:tm_memory/tm_memory.dart',
        ]);
      });
    });
  });

  group('models', () {
    setUp(() {
      business({'models': '../models'});
      put('models/pubspec.yaml', 'name: models\n');
    });

    test('still resolves by file name, the convention add-model writes', () {
      put('models/lib/task.dart', 'class Task {}\n');
      expect(importsFor('IMap<int, Task>'), ['package:models/task.dart']);
    });

    test('resolves a union case through the redirect', () {
      put('models/lib/result.dart', '''
sealed class Result with _\$Result {
  const factory Result.success() = ResultSuccess;
}
''');
      expect(importsFor('ResultSuccess?'), ['package:models/result.dart']);
    });

    test('resolves a type in a subdirectory', () {
      // The old walk was `recursive: false`, so `models/lib/converters/` was as
      // invisible as another package was.
      put('models/lib/converters/instant.dart', 'class InstantConverter {}\n');
      expect(importsFor('InstantConverter'), [
        'package:models/converters/instant.dart',
      ]);
    });

    test('a name nothing declares resolves to nothing', () {
      put('models/lib/task.dart', 'class Task {}\n');
      expect(importsFor('String?'), isEmpty);
      expect(importsFor('TaskList'), isEmpty);
    });

    test('a file named after the type but not declaring it is not it', () {
      // The lookup used to answer from the file *name* — `Task` is in
      // `task.dart` — without ever opening it. A repository where that
      // convention does not hold got `package:models/task.dart` for `Task`: an
      // import that resolves and does not supply the name, which is the one
      // failure this module says it cannot have.
      put('models/lib/task.dart', 'class TaskList {}\n');
      put('models/lib/other.dart', 'class Task {}\n');
      expect(importsFor('Task'), ['package:models/other.dart']);
      expect(importsFor('TaskList'), ['package:models/task.dart']);
    });
  });

  group('every declaration form Dart has', () {
    // The pre-filter that keeps the widened search affordable is a *second*
    // reading of "what is a declaration", written in regex against the text
    // while `_declares` reads the tree. A form the tree accepts and the text
    // rejects is silent: the file is never parsed, so the declaration is never
    // seen and the import is never written. This is the assertion that the
    // cheap reading stays no narrower than the authoritative one.
    const forms = {
      'class': 'class Shape {}',
      'abstract class': 'abstract class Shape {}',
      'abstract final class': 'abstract final class Shape {}',
      'sealed class': 'sealed class Shape {}',
      'base class': 'base class Shape {}',
      'interface class': 'interface class Shape {}',
      'mixin class': 'mixin class Shape {}',
      'generic class': 'class Shape<T extends num> {}',
      'enum': 'enum Shape { a, b }',
      'mixin': 'mixin Shape {}',
      'extension type': 'extension type Shape(int i) {}',
      'extension type const': 'extension type const Shape(int i) {}',
      'typedef': 'typedef Shape = void Function();',
      'legacy typedef': 'typedef void Shape(int a);',
    };

    forms.forEach((label, source) {
      test('$label is found', () {
        business({'models': '../models'});
        put('models/pubspec.yaml', 'name: models\n');
        put('models/lib/shape.dart', '$source\n');
        expect(
          importsFor('Shape?'),
          ['package:models/shape.dart'],
          reason: source,
        );
      });
    });

    test('a union case is found through its redirect', () {
      business({'models': '../models'});
      put('models/pubspec.yaml', 'name: models\n');
      put('models/lib/shape.dart', '''
sealed class Shape with _\$Shape {
  const factory Shape.round() = ShapeRound;
}
''');
      expect(importsFor('ShapeRound'), ['package:models/shape.dart']);
    });
  });

  group('two packages declaring one name', () {
    setUp(() {
      business({'models': '../models', 'tm_core': '../packages/tm_core'});
      put('models/pubspec.yaml', 'name: models\n');
      put('models/lib/clock.dart', 'class Clock {}\n');
      put('packages/tm_core/pubspec.yaml', 'name: tm_core\n');
      put('packages/tm_core/lib/tm_core.dart', "export 'src/clock.dart';\n");
      put('packages/tm_core/lib/src/clock.dart', 'class Clock {}\n');
    });

    test('resolve to nothing rather than to a guess', () {
      // A missed import is a compile error naming the type. A wrong one binds
      // silently to the other package's class. Only the first is recoverable by
      // reading the error, so ambiguity is answered as "I do not know".
      expect(importsFor('Clock'), isEmpty);
    });
  });

  group('the prune probe', () {
    setUp(() {
      business({'tm_memory': '../packages/tm_memory'});
      put('packages/tm_memory/pubspec.yaml', 'name: tm_memory\n');
      put('packages/tm_memory/lib/tm_memory.dart', '''
export 'src/digest.dart';
export 'src/record.dart';
''');
      put('packages/tm_memory/lib/src/digest.dart', 'class MemoryDigest {}\n');
      put('packages/tm_memory/lib/src/record.dart', 'class MemoryRecord {}\n');
    });

    test('keeps the import while any name it supplies survives', () {
      final probe = inSourceIndex(
        () => ProjectTypeImports.probeFor(
          FrxWorkspace(root),
          'package:tm_memory/tm_memory.dart',
        ),
      );
      // Both names come through one entry point, so the sibling keeps it alive.
      expect(probe('final MemoryRecord? last;'), isTrue);
      expect(probe('final String? last;'), isFalse);
    });
  });

  group('cost', () {
    // The widened search space is the whole dependency closure, and the thing
    // that keeps it affordable is that a miss never parses. Asserted rather
    // than measured once by hand: a pre-filter that quietly stops filtering is
    // invisible until somebody times `add-field`.
    setUp(() {
      business({'tm_core': '../packages/tm_core'});
      put('packages/tm_core/pubspec.yaml', 'name: tm_core\n');
      put('packages/tm_core/lib/tm_core.dart', "export 'src/task.dart';\n");
      for (var i = 0; i < 40; i++) {
        put('packages/tm_core/lib/src/file_$i.dart', '''
/// Mentions String, Task and Object the way any file does.
class Thing$i {
  final String? name = null;
  final Object? task = null;
}
''');
      }
      put('packages/tm_core/lib/src/task.dart', 'class Task {}\n');
    });

    test('a miss parses nothing', () {
      final index = SourceIndex();
      final imports = withSourceIndex(
        index,
        () => ProjectTypeImports.forAll(FrxWorkspace(root), ['String?']),
      );
      expect(imports, isEmpty);
      expect(index.parses, 0);
    });

    test('a hit parses only what it had to', () {
      final index = SourceIndex();
      final imports = withSourceIndex(
        index,
        () => ProjectTypeImports.forAll(FrxWorkspace(root), ['Task?']),
      );
      expect(imports, ['package:tm_core/tm_core.dart']);
      // The declaring file, plus the barrel found walking up to it.
      expect(index.parses, lessThan(4));
    });
  });
}
