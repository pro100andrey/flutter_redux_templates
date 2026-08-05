import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';

import '../model/selector_shape.dart';
import '../util/casing.dart';

/// The flavour of substate to scaffold.
enum SubstateKind {
  /// A single nullable `value` field with a `SetValueAction`.
  value,

  /// A `query` string plus an `IList<int> view` of results, with a
  /// `SetQueryAction`.
  search,

  /// A `byId` `IMap<int, Object>` table plus an `IList<int> view` and a waiting
  /// enum, with `Add…Action` / `Retrieve…Action`.
  table;

  static SubstateKind parse(String value) =>
      SubstateKind.values.byName(value.toLowerCase());
}

/// Produces the source files for a new AsyncRedux substate folder.
///
/// Built with `code_builder` (objects, not string templates): types are
/// [Reference]s, so the emitter's [Allocator] writes the `import` directives
/// for us — no hand-written import strings to get wrong. Output is run through
/// `dart_style` so it lands already formatted.
class SubstateScaffold {
  const SubstateScaffold(this.name, {this.kind = SubstateKind.value});

  final Casing name;
  final SubstateKind kind;

  static const _freezed = 'package:freezed_annotation/freezed_annotation.dart';
  static const _fic =
      'package:fast_immutable_collections/fast_immutable_collections.dart';

  static final _formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );

  String get _snake => name.snake;
  String get _pascal => name.pascal;
  String get _camel => name.camel;

  /// File paths (relative to the substate folder) mapped to their contents.
  Map<String, String> files() {
    switch (kind) {
      case SubstateKind.value:
        return {
          'models/${_snake}_state.dart': _emit(_valueState()),
          'actions/set_value_action.dart': _emit(
            _setFieldAction('SetValueAction', 'value'),
          ),
        };
      case SubstateKind.search:
        return {
          'models/${_snake}_state.dart': _emit(_searchState()),
          'actions/set_query_action.dart': _emit(
            _setFieldAction('SetQueryAction', 'query'),
          ),
        };
      case SubstateKind.table:
        return {
          'models/${_snake}_state.dart': _emit(_tableState()),
          'actions/add_${_snake}_action.dart': _emit(_addAction()),
          'actions/retrieve_${_snake}_action.dart': _emit(_retrieveAction()),
        };
    }
  }

  String _emit(Library library) {
    final emitter = DartEmitter(
      allocator: Allocator(),
      orderDirectives: true,
      useNullSafetySyntax: true,
    );
    return _formatter.format('${library.accept(emitter)}');
  }

  // --- shared type/expression helpers ---------------------------------------

  Reference get _appStateFromActions =>
      refer('AppState', '../../app_state.dart');

  Reference _iList(Reference of) => TypeReference(
    (t) => t
      ..symbol = 'IList'
      ..url = _fic
      ..types.add(of),
  );

  Reference _iMap(Reference key, Reference value) => TypeReference(
    (t) => t
      ..symbol = 'IMap'
      ..url = _fic
      ..types.addAll([key, value]),
  );

  /// The app's own action base (`common/action.dart`) — it carries `deps`,
  /// `env` and the `Selectors` facade, and it is what every hand-written action
  /// extends. Not generic: `Action` already pins `ReduxAction<AppState>`.
  Reference get _houseAction => refer('Action', '../../common/action.dart');

  /// A freezed `@Default(<expr>)` annotation. The inner expression is raw code;
  /// its symbols (`IListConst`, `IMapConst`) resolve via the FIC import that the
  /// field's own [Reference] type already pulls in.
  Expression _default(String constExpr) =>
      refer('Default', _freezed).call([CodeExpression(Code(constExpr))]);

  /// A named factory parameter, optionally carrying a `@Default(...)`.
  Parameter _named(String name, Reference type, {Expression? annotation}) =>
      Parameter((p) {
        p
          ..name = name
          ..named = true
          ..type = type;
        if (annotation != null) p.annotations.add(annotation);
      });

  // --- state model libraries ------------------------------------------------

  /// A `@freezed abstract class <Pascal>State with _$<Pascal>State { const
  /// factory … }` library, with an optional trailing [extraBody] (e.g. an enum).
  Library _stateLibrary(List<Parameter> params) {
    final className = '${_pascal}State';
    return Library(
      (b) => b
        ..directives.add(Directive.part('${_snake}_state.freezed.dart'))
        ..body.add(
          Class(
            (c) => c
              ..name = className
              ..abstract = true
              ..annotations.add(refer('freezed', _freezed))
              ..mixins.add(refer('_\$$className'))
              ..constructors.add(
                Constructor(
                  (ctor) => ctor
                    ..constant = true
                    ..factory = true
                    ..optionalParameters.addAll(params)
                    ..redirect = refer('_$className'),
                ),
              ),
          ),
        ),
    );
  }

  Library _valueState() => _stateLibrary([_named('value', refer('String?'))]);

  Library _searchState() => _stateLibrary([
    _named('query', refer('String?')),
    _named(
      'view',
      _iList(refer('int')),
      annotation: _default('IListConst<int>([])'),
    ),
  ]);

  Library _tableState() => _stateLibrary([
    _named(
      'table',
      _iMap(refer('int'), refer('Object')),
      annotation: _default('IMapConst<int, Object>({})'),
    ),
    _named(
      'view',
      _iList(refer('int')),
      annotation: _default('IListConst<int>([])'),
    ),
  ]);

  // --- selector facade block ------------------------------------------------

  /// The `extension type Select<Pascal>(AppState _state) implements Selector`
  /// block for this substate, plus the imports its getters need. This is emitted
  /// as text (code_builder has no `extension type` support) and wired into the
  /// repo's `selectors.dart` facade by [SelectorsSource], so the substate is
  /// reachable as `state.select.<field>` like every other one. Formatting is
  /// normalized by `dart format` on the edited `selectors.dart`.
  ({String block, List<String> imports}) selectorBlock() {
    final type = SelectorShape.typeFor(_pascal);
    String wrap(String body) => SelectorShape.declare(type: type, body: body);

    switch (kind) {
      case SubstateKind.value:
        return (
          block: wrap(
            '  /// Returns value\n'
            '  String? get value => _state.$_camel.value;\n',
          ),
          imports: const [],
        );
      case SubstateKind.search:
        return (
          block: wrap(
            '  /// Returns search query string\n'
            '  String? get query => _state.$_camel.query;\n\n'
            '  /// Returns search results view\n'
            '  IList<int> get view => _state.$_camel.view;\n',
          ),
          imports: const [_fic],
        );
      case SubstateKind.table:
        return (
          block: wrap(
            '  /// Returns waiting value\n'
            '  bool get isWaiting =>\n'
            '      _state.wait.isWaitingForType<Retrieve${_pascal}Action>();\n\n'
            '  /// Returns [IMap<int, Object>] table\n'
            '  IMap<int, Object> get table => _state.$_camel.table;\n\n'
            '  /// Returns [Object] value by id\n'
            '  Object byId(int id) => table[id]!;\n',
          ),
          imports: [_fic, '${_snake}/actions/retrieve_${_snake}_action.dart'],
        );
    }
  }

  // --- action libraries -----------------------------------------------------

  /// `class <ClassName> extends Action` that sets a single
  /// `String <field>` on this substate via `state.copyWith.<camel>(<field>: …)`.
  ///
  /// The constructor is positional, matching `ArtifactTemplates.fieldSetter` —
  /// `add-substate` and `add-field --action` drop their setters into the same
  /// `actions/` folder, and this one used to emit `({required this.value})`
  /// while the other emitted `(this.value)`. Two calling conventions for one
  /// concept, decided by which command you happened to reach for.
  Library _setFieldAction(String className, String field) => Library(
    (b) => b.body.add(
      Class(
        (c) => c
          ..name = className
          ..extend = _houseAction
          ..constructors.add(
            Constructor(
              (ctor) => ctor.requiredParameters.add(
                Parameter(
                  (p) => p
                    ..name = field
                    ..toThis = true,
                ),
              ),
            ),
          )
          ..fields.add(
            Field(
              (f) => f
                ..name = field
                ..modifier = FieldModifier.final$
                ..type = refer('String'),
            ),
          )
          ..methods.add(
            Method(
              (m) => m
                ..name = 'reduce'
                ..annotations.add(refer('override'))
                ..returns = _appStateFromActions
                ..lambda = true
                ..body = refer('state')
                    .property('copyWith')
                    .property(_camel)
                    .call([], {field: refer(field)})
                    .code,
            ),
          ),
      ),
    ),
  );

  /// `Add<Pascal>Action` — folds a list of items into the `byId` table.
  Library _addAction() {
    return Library(
      (b) => b.body.add(
        Class(
          (c) => c
            ..name = 'Add${_pascal}Action'
            ..extend = _houseAction
            ..constructors.add(
              Constructor(
                (ctor) => ctor.optionalParameters.add(
                  Parameter(
                    (p) => p
                      ..name = 'items'
                      ..named = true
                      ..required = true
                      ..toThis = true,
                  ),
                ),
              ),
            )
            ..fields.add(
              Field(
                (f) => f
                  ..name = 'items'
                  ..modifier = FieldModifier.final$
                  ..type = _iList(refer('Object')),
              ),
            )
            ..methods.addAll([
              Method(
                (m) => m
                  ..name = 'reduce'
                  ..annotations.add(refer('override'))
                  ..returns = _appStateFromActions
                  ..body = Block(
                    (bl) => bl.statements.addAll([
                      declareFinal('byId')
                          .assign(
                            _iMap(
                              refer('int'),
                              refer('Object'),
                            ).newInstanceNamed('fromValues', [], {
                              'values': refer('items'),
                              'keyMapper': refer('_idOf'),
                            }),
                          )
                          .statement,
                      declareFinal('updated')
                          .assign(
                            refer('state')
                                .property(_camel)
                                .property('table')
                                .property('addAll')
                                .call([refer('byId')]),
                          )
                          .statement,
                      refer('state')
                          .property('copyWith')
                          .property(_camel)
                          .call([], {'table': refer('updated')})
                          .returned
                          .statement,
                    ]),
                  ),
              ),
              // Fail loud until the caller wires in a real model type + id.
              Method(
                (m) => m
                  ..name = '_idOf'
                  ..docs.add(
                    '// TODO(frx): replace `Object` with your model type and return its int id.',
                  )
                  ..returns = refer('int')
                  ..lambda = true
                  ..requiredParameters.add(
                    Parameter(
                      (p) => p
                        ..name = 'item'
                        ..type = refer('Object'),
                    ),
                  )
                  ..body = refer('UnimplementedError')
                      .call([
                        literalString(
                          'Add${_pascal}Action._idOf: map your model to its int id',
                        ),
                      ])
                      .thrown
                      .code,
              ),
            ]),
        ),
      ),
    );
  }

  /// `Retrieve<Pascal>Action` — an async action behind the wait barrier.
  ///
  /// The barrier comes from the `WaitingAction` mixin rather than a hand-written
  /// `before()`/`after()` pair over an enum flag, which is what this used to
  /// emit. Two spellings of one idea is one too many: the template's own waiting
  /// actions all mix it in, `add-action -k waiting` scaffolds it, and the reader
  /// is `isWaitingForType<T>()` — keyed on the action, so no enum has to exist
  /// to name the thing being waited for.
  Library _retrieveAction() {
    return Library(
      (b) => b.body.add(
        Class(
          (c) => c
            ..name = 'Retrieve${_pascal}Action'
            ..extend = _houseAction
            ..mixins.add(refer('WaitingAction', '../../common/action.dart'))
            ..methods.addAll([
              Method(
                (m) => m
                  ..name = 'reduce'
                  ..annotations.add(refer('override'))
                  ..returns = TypeReference(
                    (t) => t
                      ..symbol = 'Future'
                      ..types.add(
                        TypeReference(
                          (x) => x
                            ..symbol = 'AppState'
                            ..url = '../../app_state.dart'
                            ..isNullable = true,
                        ),
                      ),
                  )
                  ..lambda = true
                  ..body = refer(
                    'Future',
                  ).property('value').call([refer('state')]).code,
              ),
            ]),
        ),
      ),
    );
  }
}
