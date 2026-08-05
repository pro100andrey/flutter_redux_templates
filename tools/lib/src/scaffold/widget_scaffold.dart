import '../util/casing.dart';

/// The shapes a widget in the `ui` package comes in.
///
/// The kind decides three things at once: what the widget takes in, which
/// primitive it is built from, and which states its previews enumerate. It is
/// not a style — a widget that fits none of these is a sign the package is
/// missing a primitive.
enum WidgetKind {
  /// Takes a `FieldVm<T>`; wraps `InputFormField`.
  field,

  /// Takes a `ChoiceVm<T>`; wraps `ChoiceFormField`.
  ///
  /// **Shares [field]'s `FormField` suffix, so one name holds one of the two.**
  /// `add-widget Pin -k field` and `add-widget Pin -k choice` both mean
  /// `PinFormField` in `pin_form_field.dart`; the second is refused by the
  /// overwrite guard, naming both files, and `--force` replaces rather than
  /// merges. Nothing is corrupted and nothing is silent — but after the fact
  /// the file does not say which kind wrote it, and `remove` cannot either.
  ///
  /// Left as it is deliberately. Giving `choice` its own suffix would rename
  /// the class and the file in every project already built on this convention,
  /// which is a bigger decision than the collision costs: two widgets that both
  /// wrap a form field, under one name, is a naming problem the author is
  /// better placed to resolve than the scaffolder.
  choice,

  /// A labelled action; wraps `Button`.
  action,

  /// Draws a render model. The model is pure data and the tap handler is a
  /// widget parameter — see the generated doc comment.
  view,

  /// Wraps other widgets; takes a `child`.
  container;

  /// The folder this kind usually lives in, offered first by completion.
  /// `view` has none: a card, a tile, a row and a header are all views.
  String? get homeDir => switch (this) {
    field || choice => 'inputs',
    action => 'buttons',
    container => 'containers',
    view => null,
  };
}

/// The two files a widget is made of: the widget itself, and its previews in
/// the mirrored `lib/previews/` tree.
///
/// Nothing imports the preview file, so it stays out of the app's compile
/// graph — which is also why the widget file never imports preview machinery.
class WidgetScaffold {
  WidgetScaffold({required Casing name, required this.kind, required this.dir})
    : name = _stripSuffix(name, kind);

  /// The name with any suffix the kind adds already removed, so `pin_field`
  /// with `-k field` yields `PinFormField`, not `PinFieldFormField`.
  final Casing name;
  final WidgetKind kind;

  /// The folder under `ui/lib/`, e.g. `inputs`. Also where the preview mirror
  /// puts its copy.
  final String dir;

  /// `PinFormField`, `SubmitButton`, `ExerciseCard`.
  ///
  /// [name] is already stripped by the constructor, so this appends and does not
  /// strip again. Making it call [classNameFor] instead stripped twice on the
  /// scaffolding path and once on the removal path — `add-widget
  /// SubmitButtonButton -k action` wrote `submit_button.dart` while `remove
  /// SubmitButtonButton` looked for `submit_button_button.dart`, which is the
  /// same disagreement the public accessor was added to end, reintroduced by
  /// ending it carelessly.
  String get className => _classOf(name, kind);

  /// The class `add-widget <typed> --kind <kind>` writes, for the name as the
  /// user typed it.
  ///
  /// Public because the convention has to be readable *backwards*. `remove`
  /// derives a path from what it is handed, and it used to derive
  /// `<typed>.dart` — so `add-widget Pin --dir inputs --kind field` wrote
  /// `pin_form_field.dart` and `frx remove Pin --kind widget` exited 70,
  /// "no widget named Pin". The two directions agreed only for the kinds that
  /// add no suffix, which is why every round-trip test happened to pass.
  ///
  /// Idempotent on an already-stripped name: [_stripSuffix] only strips when
  /// the result would be non-empty, so `Pin` stays `Pin`.
  static String classNameFor(Casing typed, WidgetKind kind) =>
      _classOf(_stripSuffix(typed, kind), kind);

  /// The suffix rule itself, over a name already reduced to its stem. One
  /// statement, so the two entry points differ only in whether they strip.
  static String _classOf(Casing stem, WidgetKind kind) =>
      '${stem.pascal}${_suffixFor(kind).pascalOrEmpty}';

  /// The basename `add-widget <typed> --kind <kind>` writes, and the one
  /// `remove` has to look for. Also the preview's basename in the mirror.
  static String fileNameFor(Casing typed, WidgetKind kind) =>
      '${_snakeOf(classNameFor(typed, kind))}.dart';

  /// The render model for a [WidgetKind.view], e.g. `ExerciseCardVm`.
  String get vmClassName => '${className}Vm';

  /// Derived from [className], not from [fileNameFor]: `name` is stripped
  /// already, and routing it through the public accessor stripped it a second
  /// time — so the class said `SubmitButtonButton` while the file said
  /// `submit_button.dart`.
  String get fileName => '${_snakeOf(className)}.dart';

  /// The value type of the view-model a `field`/`choice` takes. Generated as a
  /// nullable string — the common case, and a one-word edit otherwise.
  static const _valueType = 'String?';

  /// An import of `ui/lib/<target>/<file>` from the widget's own folder. Every
  /// widget folder sits one level under `lib/`, so a sibling is `../<target>/`.
  String _sibling(String target, String file) =>
      dir == target ? file : '../$target/$file';

  /// The same, from `ui/lib/previews/<dir>/` — always two levels up.
  String _fromPreview(String target, String file) => '../../$target/$file';

  String widget() => switch (kind) {
    WidgetKind.field => _fieldWidget(),
    WidgetKind.choice => _choiceWidget(),
    WidgetKind.action => _actionWidget(),
    WidgetKind.view => _viewWidget(),
    WidgetKind.container => _containerWidget(),
  };

  String preview() => switch (kind) {
    WidgetKind.field => _fieldPreview(),
    WidgetKind.choice => _choicePreview(),
    WidgetKind.action => _actionPreview(),
    WidgetKind.view => _viewPreview(),
    WidgetKind.container => _containerPreview(),
  };

  // --- widgets --------------------------------------------------------------

  String _fieldWidget() =>
      '''
import 'package:flutter/material.dart';

import '${_sibling('models', 'value_changed.dart')}';
import '${_sibling('inputs', 'input_form_field.dart')}';

// TODO(frx): describe what this field asks for, and when to use it.
class $className extends StatelessWidget {
  const $className({required this.vm, super.key});

  final FieldVm<$_valueType> vm;

  @override
  Widget build(BuildContext context) => InputFormField(
    vm: vm,
    // TODO(frx): the label belongs in localization — S.current.
    labelText: '${name.pascal}',
  );
}
''';

  String _choiceWidget() =>
      '''
import 'package:flutter/material.dart';

import '${_sibling('models', 'value_changed.dart')}';
import '${_sibling('inputs', 'choice_form_field.dart')}';

// TODO(frx): describe what this picks. Its items are data — the connector
// resolves their labels, where the locale and the domain live.
class $className extends StatelessWidget {
  const $className({required this.vm, super.key});

  final ChoiceVm<$_valueType> vm;

  @override
  Widget build(BuildContext context) => ChoiceFormField<$_valueType>(
    vm: vm,
    // TODO(frx): the label belongs in localization — S.current.
    labelText: '${name.pascal}',
  );
}
''';

  String _actionWidget() =>
      '''
import 'package:flutter/material.dart';

import '${_sibling('buttons', 'button.dart')}';

// TODO(frx): describe what this action does.
class $className extends StatelessWidget {
  const $className({required this.onPressed, this.expand = false, super.key});

  /// Null disables the button; the theme dims it.
  final VoidCallback? onPressed;

  /// Stretch to the available width instead of hugging.
  final bool expand;

  @override
  Widget build(BuildContext context) => Button.primary(
    // TODO(frx): the label belongs in localization — S.current.
    label: '${name.pascal}',
    onPressed: onPressed,
    expand: expand,
  );
}
''';

  String _viewWidget() =>
      '''
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '${_sibling('theme', 'spacing.dart')}';

/// What [$className] draws.
///
/// Pure data, so it is `const`-constructible and every field is in [props].
/// The tap handler is not here: what a tap means depends on where the widget is
/// placed, and a callback outside [props] would make two of these compare equal
/// while pointing at different rows.
///
/// [id] carries the identity the composer passes back to its own callback.
final class $vmClassName extends Equatable {
  const $vmClassName({required this.id, required this.title});

  final String id;
  final String title;

  @override
  List<Object?> get props => [id, title];
}

// TODO(frx): describe what this shows, and what composes it.
class $className extends StatelessWidget {
  const $className({required this.vm, this.onTap, super.key});

  final $vmClassName vm;

  /// The composer decides what a tap means — in a list, one handler keyed by
  /// [$vmClassName.id] rather than a closure per row.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // TODO(frx): compose from the package's primitives.
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: Insets.md,
        child: Text(vm.title, style: theme.textTheme.titleSmall),
      ),
    );
  }
}
''';

  String _containerWidget() =>
      '''
import 'package:flutter/material.dart';

import '${_sibling('theme', 'spacing.dart')}';

// TODO(frx): describe what this wraps, and what chrome it adds.
class $className extends StatelessWidget {
  const $className({required this.child, this.padding = Insets.md, super.key});

  final Widget child;

  /// Room around the content.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) =>
      // TODO(frx): AppCard is the package's card treatment.
      Padding(padding: padding, child: child);
}
''';

  // --- previews -------------------------------------------------------------

  String get _previewFn => name.camel + _suffixFor(kind).pascalOrEmpty;

  String _previewHeader(List<String> imports) =>
      '''
import 'package:flutter/widgets.dart';

${imports.map((i) => "import '$i';").join('\n')}
''';

  String _fieldPreview() =>
      '''
${_previewHeader([_fromPreview(dir, fileName), _fromPreview('models', 'value_changed.dart'), _fromPreview('theme', 'preview.dart')])}
@AppPreview(name: 'default', group: '$className')
Widget ${_previewFn}Preview() =>
    const $className(vm: FieldVm(value: 'Value', onChanged: _ignore));

@AppPreview(name: 'error', group: '$className')
Widget ${_previewFn}ErrorPreview() => const $className(
  vm: FieldVm(value: null, onChanged: _ignore, error: 'Required'),
);

@AppPreview(name: 'disabled', group: '$className')
Widget ${_previewFn}DisabledPreview() => const $className(
  vm: FieldVm(value: 'Value', onChanged: _ignore, enabled: false),
);

void _ignore($_valueType _) {}
''';

  String _choicePreview() =>
      '''
${_previewHeader([_fromPreview(dir, fileName), _fromPreview('models', 'value_changed.dart'), _fromPreview('theme', 'preview.dart')])}
const _items = [
  ChoiceItemVm(value: 'one', label: 'One'),
  ChoiceItemVm(value: 'two', label: 'Two'),
];

@AppPreview(name: 'selected', group: '$className')
Widget ${_previewFn}Preview() => const $className(
  vm: ChoiceVm(value: 'one', items: _items, onChanged: _ignore),
);

/// A value outside the items — the control reads as "nothing picked".
@AppPreview(name: 'empty', group: '$className')
Widget ${_previewFn}EmptyPreview() => const $className(
  vm: ChoiceVm(value: null, items: _items, onChanged: _ignore),
);

@AppPreview(name: 'disabled', group: '$className')
Widget ${_previewFn}DisabledPreview() => const $className(
  vm: ChoiceVm(
    value: 'one',
    items: _items,
    enabled: false,
    onChanged: _ignore,
  ),
);

void _ignore($_valueType _) {}
''';

  String _actionPreview() =>
      '''
${_previewHeader([_fromPreview(dir, fileName), _fromPreview('theme', 'preview.dart')])}
@AppPreview(name: 'default', group: '$className')
Widget ${_previewFn}Preview() => $className(onPressed: () {});

/// Null `onPressed` is the disabled state — there is no `enabled` flag.
@AppPreview(name: 'disabled', group: '$className')
Widget ${_previewFn}DisabledPreview() => const $className(onPressed: null);
''';

  String _viewPreview() =>
      '''
${_previewHeader([_fromPreview(dir, fileName), _fromPreview('theme', 'preview.dart')])}
const _sample = $vmClassName(id: '1', title: '$className');

@AppPreview(name: 'default', group: '$className')
Widget ${_previewFn}Preview() => $className(vm: _sample, onTap: () {});

/// No handler — the composer gave it none, so it does not react to a tap.
@AppPreview(name: 'not tappable', group: '$className')
Widget ${_previewFn}FlatPreview() => const $className(vm: _sample);
''';

  String _containerPreview() =>
      '''
${_previewHeader([_fromPreview(dir, fileName), _fromPreview('theme', 'preview.dart')])}
@AppPreview(name: 'default', group: '$className')
Widget ${_previewFn}Preview() =>
    const $className(child: Text('Content'));
''';

  // --- naming ---------------------------------------------------------------

  static _Suffix _suffixFor(WidgetKind kind) => switch (kind) {
    WidgetKind.field || WidgetKind.choice => const _Suffix(['form', 'field']),
    WidgetKind.action => const _Suffix(['button']),
    WidgetKind.view || WidgetKind.container => const _Suffix([]),
  };

  /// Drops a suffix the kind is about to add back, so `pin_form_field` and
  /// `pin` both yield `PinFormField`. Also drops the shorter `field`, the way
  /// the name is usually typed.
  static Casing _stripSuffix(Casing name, WidgetKind kind) {
    var words = name.words;
    for (final candidate in _strippable(kind)) {
      if (_endsWith(words, candidate) && words.length > candidate.length) {
        words = words.sublist(0, words.length - candidate.length);
        break;
      }
    }
    return Casing(words);
  }

  static List<List<String>> _strippable(WidgetKind kind) => switch (kind) {
    WidgetKind.field || WidgetKind.choice => const [
      ['form', 'field'],
      ['field'],
    ],
    WidgetKind.action => const [
      ['button'],
    ],
    WidgetKind.view || WidgetKind.container => const [],
  };

  static bool _endsWith(List<String> words, List<String> suffix) {
    if (suffix.isEmpty || words.length < suffix.length) return false;
    final start = words.length - suffix.length;
    for (var i = 0; i < suffix.length; i++) {
      if (words[start + i] != suffix[i]) return false;
    }
    return true;
  }

  static String _snakeOf(String pascal) => Casing.parse(pascal).snake;
}

/// A class-name suffix as words, e.g. `['form', 'field']` → `FormField`.
class _Suffix {
  const _Suffix(this.words);

  final List<String> words;

  String get pascalOrEmpty =>
      words.isEmpty ? '' : Casing(words.toList()).pascal;
}
