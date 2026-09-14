import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';

import '../model/selector_shape.dart';
import '../redux/selectors_source.dart' show SelectorsSource;
import '../util/casing.dart';
import 'type_imports.dart';

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
  static const String _fic = TypeImports.fastImmutableCollections;
  static const _appState = '../../app_state.dart';
  static const _action = '../../common/action.dart';

  static final _formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );

  String get _snake => name.snake;
  String get _pascal => name.pascal;
  String get _camel => name.camel;

  /// File paths (relative to the substate folder) mapped to their contents.
  ///
  /// The state model first, then the actions — the order the plan narrates
  /// them in.
  Map<String, String> files() => {
    'models/${_snake}_state.dart': _emit(_state()),
    for (final entry in _actions().entries) entry.key: _emit(entry.value),
  };

  Library _state() => switch (kind) {
    SubstateKind.value => _valueState(),
    SubstateKind.search => _searchState(),
    SubstateKind.table => _tableState(),
  };

  Map<String, Library> _actions() => switch (kind) {
    SubstateKind.value => {
      'actions/set_value_action.dart': _setFieldAction(
        'SetValueAction',
        'value',
      ),
    },
    SubstateKind.search => {
      'actions/set_query_action.dart': _setFieldAction(
        'SetQueryAction',
        'query',
      ),
    },
    SubstateKind.table => {
      'actions/add_${_snake}_action.dart': _addAction(),
      'actions/retrieve_${_snake}_action.dart': _retrieveAction(),
    },
  };

  String _emit(Library library) {
    // A fresh emitter per library: the allocator collects the imports the
    // library's references need, so it cannot be shared between two.
    final emitter = DartEmitter(
      allocator: Allocator(),
      orderDirectives: true,
      useNullSafetySyntax: true,
    );
    return _formatter.format('${library.accept(emitter)}');
  }

  // --- shared type/expression helpers ---------------------------------------

  static final Reference _appStateFromActions = refer('AppState', _appState);

  /// The app's own action base (`common/action.dart`) — it carries `deps`,
  /// `env` and the `Selectors` facade, and it is what every hand-written action
  /// extends. Not generic: `Action` already pins `ReduxAction<AppState>`.
  static final Reference _houseAction = refer('Action', _action);

  static Reference _iList(Reference of) => TypeReference(
    (t) => t
      ..symbol = 'IList'
      ..url = _fic
      ..types.add(of),
  );

  static Reference _iMap(Reference key, Reference value) => TypeReference(
    (t) => t
      ..symbol = 'IMap'
      ..url = _fic
      ..types.addAll([key, value]),
  );

  /// `IList<int>` — the ordered view every listing substate carries.
  static final Reference _intList = _iList(refer('int'));

  /// `IMap<int, Object>` — the table until the caller names its model type.
  static final Reference _intObjectMap = _iMap(refer('int'), refer('Object'));

  /// A freezed `@Default(<expr>)` annotation. The inner expression is raw
  /// code; its symbols (`IListConst`, `IMapConst`) resolve via the FIC import
  /// that the field's own [Reference] type already pulls in.
  static Expression _default(String constExpr) =>
      refer('Default', _freezed).call([CodeExpression(Code(constExpr))]);

  /// A named factory parameter, optionally carrying a `@Default(...)`.
  static Parameter _named(
    String name,
    Reference type, {
    Expression? annotation,
  }) => Parameter((p) {
    p
      ..name = name
      ..named = true
      ..type = type;
    if (annotation != null) {
      p.annotations.add(annotation);
    }
  });

  /// The `view` field `search` and `table` share: `IList<int>`, empty by
  /// default.
  static final Parameter _viewParam = _named(
    'view',
    _intList,
    annotation: _default('IListConst<int>([])'),
  );

  /// A `final <type> <name>;` field.
  static Field _finalField(String name, Reference type) => Field(
    (f) => f
      ..name = name
      ..modifier = FieldModifier.final$
      ..type = type,
  );

  /// A constructor taking one positional `this.<field>`.
  static Constructor _positionalCtor(String field) => Constructor(
    (ctor) => ctor.requiredParameters.add(
      Parameter(
        (p) => p
          ..name = field
          ..toThis = true,
      ),
    ),
  );

  /// An `@override … reduce()` returning [returns], with [body] as either an
  /// arrow ([lambda]) or a block.
  static Method _reduce({
    required Reference returns,
    required Code body,
    bool? lambda,
  }) => Method(
    (m) => m
      ..name = 'reduce'
      ..annotations.add(refer('override'))
      ..returns = returns
      ..lambda = lambda
      ..body = body,
  );

  /// `state.copyWith.<camel>(<args>)` — how a reducer writes its own slice.
  Expression _copyWithSlice(Map<String, Expression> args) =>
      refer('state').property('copyWith').property(_camel).call([], args);

  // --- state model libraries ------------------------------------------------

  /// A `@freezed abstract class <Pascal>State with _$<Pascal>State` library,
  /// holding one `const factory …` over [params].
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

  Library _searchState() =>
      _stateLibrary([_named('query', refer('String?')), _viewParam]);

  /// How the `Add<Pascal>Action` reducer reaches its own slice.
  ///
  /// `tasks.table` — through the facade — because that is how a reducer reads
  /// here and it is the only read `frx graph` can see; the scaffolder used to
  /// emit `state.tasks.table`, which is the shape the router tells an agent not
  /// to write.
  ///
  /// **Except when the name is taken.** Inside `reduce()` the `byId` local and
  /// the base class's `state`/`deps`/`env` are in scope, and a substate named
  /// for one of them shadows the facade getter — `byId.table` would resolve to
  /// the local `IMap` and not to the slice. There the qualified form is the
  /// correct one. (The action's own payload field is `_items`, which is why it
  /// is not on this list: a leading underscore is not a name a substate can
  /// have.)
  Expression get _tableRead =>
      const {'byId', 'state', 'deps', 'env', 'store'}.contains(_camel)
      ? refer('state').property(_camel)
      : refer(_camel);

  Library _tableState() => _stateLibrary([
    _named(
      'table',
      _intObjectMap,
      annotation: _default('IMapConst<int, Object>({})'),
    ),
    _viewParam,
  ]);

  // --- selector facade block ------------------------------------------------

  /// The `extension type Select<Pascal>(AppState _state) implements Selector`
  /// block for this substate, plus the imports its getters need. This is
  /// emitted as text (code_builder has no `extension type` support) and wired
  /// into the repo's `selectors.dart` facade by [SelectorsSource], so the
  /// substate is reachable as `state.select.<field>` like every other one.
  /// Formatting is normalized by `dart format` on the edited `selectors.dart`.
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
            '      '
            '_state.wait.isWaitingForType<Retrieve${_pascal}Action>();\n\n'
            '  /// Returns [IMap<int, Object>] table\n'
            '  IMap<int, Object> get table => _state.$_camel.table;\n\n'
            '  /// Returns [Object] value by id\n'
            '  Object byId(int id) => table[id]!;\n\n'
            // The state declares `view` and the facade did not expose it, so
            // the one ordering a table has was reachable only as
            // `state.<slice>.view` — the spelling this architecture's own rule
            // forbids, and the one a reducer written to that rule cannot use.
            // `search` had the getter all along; `table` was the copy that
            // missed it.
            '  /// Returns the ordered view of the table\n'
            '  IList<int> get view => _state.$_camel.view;\n',
          ),
          imports: [_fic, '$_snake/actions/retrieve_${_snake}_action.dart'],
        );
    }
  }

  // --- action libraries -----------------------------------------------------

  /// `class <ClassName> extends Action` that sets a single `String <field>` on
  /// this substate via `state.copyWith.<camel>(<field>: …)`.
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
          ..constructors.add(_positionalCtor(field))
          ..fields.add(_finalField(field, refer('String')))
          ..methods.add(
            _reduce(
              returns: _appStateFromActions,
              lambda: true,
              body: _copyWithSlice({field: refer(field)}).code,
            ),
          ),
      ),
    ),
  );

  /// `Add<Pascal>Action` — folds a list of items into the `byId` table.
  Library _addAction() => Library(
    (b) => b.body.add(
      Class(
        (c) => c
          ..name = 'Add${_pascal}Action'
          ..extend = _houseAction
          // Private, and positional because a private named parameter is not a
          // thing a caller can pass. **The name is the point.** `Action` mixes
          // in `Selectors`, which gains a getter per substate, so a public
          // field here collides with the facade the same command generates:
          // `frx add-substate items -k table` wrote `AddItemsAction.items` over
          // `Selectors.items` and the analyzer refused it, with
          // `'IList<Object> Function()' isn't a valid override of`
          // `'SelectItems Function()'`.
          // A leading underscore cannot be a substate's camel name, so this
          // collision is not merely unlikely, it is unreachable.
          ..constructors.add(_positionalCtor('_items'))
          ..fields.add(_finalField('_items', _iList(refer('Object'))))
          ..methods.addAll([
            _reduce(
              returns: _appStateFromActions,
              body: Block(
                (bl) => bl.statements.addAll([
                  declareFinal('byId')
                      .assign(
                        _intObjectMap.newInstanceNamed('fromValues', [], {
                          'values': refer('_items'),
                          'keyMapper': refer('_idOf'),
                        }),
                      )
                      .statement,
                  declareFinal('updated')
                      .assign(
                        _tableRead.property('table').property('addAll').call([
                          refer('byId'),
                        ]),
                      )
                      .statement,
                  _copyWithSlice({
                    'table': refer('updated'),
                  }).returned.statement,
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
                        'Add${_pascal}Action._idOf: map your model to its int '
                        'id',
                      ),
                    ])
                    .thrown
                    .code,
            ),
          ]),
      ),
    ),
  );

  /// `Retrieve<Pascal>Action` — an async action behind the wait barrier.
  ///
  /// The barrier comes from the `WaitingAction` mixin rather than a
  /// hand-written `before()`/`after()` pair over an enum flag, which is what
  /// this used to emit. Two spellings of one idea is one too many: the
  /// template's own waiting actions all mix it in, `add-action -k waiting`
  /// scaffolds it, and the reader is `isWaitingForType<T>()` — keyed on the
  /// action, so no enum has to exist to name the thing being waited for.
  Library _retrieveAction() => Library(
    (b) => b.body.add(
      Class(
        (c) => c
          ..name = 'Retrieve${_pascal}Action'
          ..extend = _houseAction
          ..mixins.add(refer('WaitingAction', _action))
          ..methods.add(
            _reduce(
              returns: TypeReference(
                (t) => t
                  ..symbol = 'Future'
                  ..types.add(
                    TypeReference(
                      (x) => x
                        ..symbol = 'AppState'
                        ..url = _appState
                        ..isNullable = true,
                    ),
                  ),
              ),
              lambda: true,
              body: refer(
                'Future',
              ).property('value').call([refer('state')]).code,
            ),
          ),
      ),
    ),
  );
}
