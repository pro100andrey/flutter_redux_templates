import 'package:test/test.dart';
import 'package:tools/src/scaffold/widget_scaffold.dart';
import 'package:tools/src/util/casing.dart';

import 'support/parses.dart';

/// The widget archetypes. What matters per kind: the class name (suffixes are
/// added, not doubled), the import paths (which shift with `--dir`), and that
/// both files are valid Dart.
void main() {
  WidgetScaffold make(String name, WidgetKind kind, {String dir = 'inputs'}) =>
      WidgetScaffold(name: Casing.parse(name), kind: kind, dir: dir);

  group('naming', () {
    test('a kind adds its own suffix', () {
      expect(make('pin', WidgetKind.field).className, 'PinFormField');
      expect(make('submit', WidgetKind.action).className, 'SubmitButton');
    });

    test('a suffix already typed is not doubled', () {
      expect(
        make('pin_form_field', WidgetKind.field).className,
        'PinFormField',
      );
      expect(make('pin_field', WidgetKind.field).className, 'PinFormField');
      expect(
        make('submit_button', WidgetKind.action).className,
        'SubmitButton',
      );
    });

    test('view and container take the name as given', () {
      expect(make('exercise_card', WidgetKind.view).className, 'ExerciseCard');
      expect(make('panel', WidgetKind.container).className, 'Panel');
    });

    test('a name that is only the suffix keeps it', () {
      // Stripping would leave nothing to name the class after.
      expect(make('field', WidgetKind.field).className, 'FieldFormField');
      expect(make('button', WidgetKind.action).className, 'ButtonButton');
    });

    test('the file name follows the class, not the typed name', () {
      expect(
        make('pin_field', WidgetKind.field).fileName,
        'pin_form_field.dart',
      );
    });
  });

  group('imports follow --dir', () {
    test('a primitive in the same folder is imported without a hop', () {
      expect(
        make('pin', WidgetKind.field, dir: 'inputs').widget(),
        contains("import 'input_form_field.dart';"),
      );
    });

    test('a primitive in another folder goes up one level', () {
      expect(
        make('pin', WidgetKind.field, dir: 'forms').widget(),
        contains("import '../inputs/input_form_field.dart';"),
      );
    });
  });

  group('conventions the templates carry', () {
    test('a view model holds an id and no callback', () {
      final source = make(
        'exercise_card',
        WidgetKind.view,
        dir: 'cards',
      ).widget();
      expect(source, contains('final String id;'));
      expect(source, contains('List<Object?> get props => [id, title];'));
      // The handler is the composer's, so it is a widget parameter.
      expect(source, contains('final VoidCallback? onTap;'));
      expect(source, isNot(contains('onTap;\n\n  @override\n  List<Object?>')));
    });
  });

  group('the file parses', () {
    for (final kind in WidgetKind.values) {
      test('${kind.name} widget', () {
        expectParses(make('thing', kind, dir: 'tiles').widget());
      });
    }
  });
}
