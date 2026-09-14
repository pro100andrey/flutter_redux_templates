import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../ast/construction.dart';
import '../ast/declarations.dart';
import '../ast/function_bodies.dart';
import '../ast/source_index.dart';
import '../redux/ast_edit.dart';
import '../refusal.dart';

/// One argument the destination route takes — `id` of type `int`.
class NavParam {
  const NavParam(this.name, this.type);

  final String name;
  final String type;
}

/// Reads and edits a page connector and its dumb page to add a navigation hop.
///
/// A hop is not one edit but five, spread over two packages: the callback in
/// `_Vm`, the `dispatch(GoAction.push(...))` that fills it, the argument handed
/// down in `builder:`, and the parameter plus field on the page itself. Doing
/// four of them leaves code that does not compile, which is why they live in
/// one place rather than in the command.
class NavSource {
  const NavSource();

  /// The route's parameters, read from the destination connector's fields —
  /// `final int id;` next to a `this.id` constructor parameter.
  ///
  /// Read from the connector rather than from the `:id` segments of the route
  /// path: the path says a parameter exists, only the field says its type.
  static List<NavParam> paramsOf(File connector) {
    if (!connector.existsSync()) {
      return const [];
    }
    for (final d in classesIn(sourceIndex.unitFor(connector))) {
      if (!d.namePart.typeName.lexeme.endsWith('Connector')) {
        continue;
      }
      // Only what the constructor binds as `this.<name>`, in the order it
      // takes them. Every field would sweep up anything the connector holds
      // for itself — a controller, a cached value — and hand it to a route
      // constructor that does not accept it.
      final types = fieldTypesOf(d);
      return [
        for (final c in d.body.members.whereType<ConstructorDeclaration>())
          for (final param in c.parameters.parameters)
            if (param is FieldFormalParameter)
              if (types[param.name.lexeme] case final type?)
                NavParam(param.name.lexeme, type),
      ];
    }
    return const [];
  }

  /// Wires the hop into the *source* connector: the `_Vm` callback, the
  /// dispatch that fills it, the argument passed to the page, and the two
  /// imports the route and `GoAction` need.
  ///
  /// [args] is what the route constructor is handed, already spelled — `id: id`
  /// for a callback that takes the id, `productId: connector.id` for one the
  /// connector already holds.
  Edited wireConnector({
    required String original,
    required String callback,
    required String routeType,
    required String method,
    required String args,
    required List<NavParam> params,
    required String pageClass,
  }) {
    // The imports go in first, one re-parse each — see [addImports] for why
    // two computed against the same parse both aim at the spot the other is
    // about to take. Every structural offset below is then read off the text
    // they are already in.
    final added = addImports(original, const [
      '../navigation/app_router.dart',
      '../navigation/go_action.dart',
    ]);
    final content = added.source;
    final changes = [...added.changes];

    final unit = parseString(content: content, throwIfDiagnostics: false).unit;
    final vm = classNamed(unit, '_Vm');
    final factory = classNamed(unit, '_Factory');
    if (vm == null || factory == null) {
      throw const FrxRefusal(
        'the connector has no `_Vm`/`_Factory` pair — it was not written by '
        'frx, so where the callback goes is a guess',
      );
    }
    if (declaresField(vm, callback)) {
      return Edited.nothing(original);
    }

    final signature = _signature(params);
    final edits = <Edit>[];

    // `_Vm({required this.onTapItem, …})` plus the field it initialises.
    final ctor = _constructor(vm);
    if (ctor == null) {
      throw const FrxRefusal('`_Vm` has no constructor to add the callback to');
    }
    edits
      ..add(_namedParamInsertion(ctor, 'required this.$callback'))
      ..add(Edit.insert(vm.end - 1, '\n  final $signature $callback;\n'));
    changes.add('_Vm.$callback ($signature)');

    // `_Vm fromStore() => _Vm(onTapItem: (id) => dispatch(…))`.
    final created = _vmCreation(factory);
    if (created == null) {
      throw const FrxRefusal(
        '`_Factory.fromStore` does not return a `_Vm(...)`',
      );
    }
    final lambda = params.map((p) => p.name).join(', ');
    // `const` exactly when the route takes nothing. `pro_lints` turns on
    // `prefer_const_constructors`, so a scaffolded
    // `GoAction.push(TasksRoute())` was code this repository's own analyzer
    // refuses — and with arguments the keyword would be wrong, so it cannot
    // simply always be there.
    final route = args.isEmpty ? 'const $routeType()' : '$routeType($args)';
    final dispatched = 'GoAction.$method($route)';
    edits.add(
      insertIntoList(
        elements: created.arguments.arguments,
        closer: created.arguments.rightParenthesis,
        element: '$callback: ($lambda) => dispatch($dispatched)',
      ),
    );
    changes.add('dispatch($dispatched)');

    // `builder: (context, vm) => CatalogPage(onTapItem: vm.onTapItem)`. The
    // page gains an argument, so a `const` construction cannot stay const.
    final page = Construction.firstIn(
      unit,
      (made) => made.fullName == pageClass,
    );
    if (page != null) {
      final keyword = page.constKeyword;
      if (keyword != null) {
        edits.add(Edit.replace(keyword.offset, page.nameOffset, ''));
      }
      edits.add(
        insertIntoList(
          elements: page.arguments.arguments,
          closer: page.arguments.rightParenthesis,
          element: '$callback: vm.$callback',
        ),
      );
      changes.add('$pageClass($callback: vm.$callback)');
    }

    return Edited(source: applyEdits(content, edits), changes: changes);
  }

  /// Wires the receiving end into the dumb page: the constructor parameter and
  /// the field. What the page *does* with the callback is left alone — which
  /// button calls it is the one part of this frx cannot know.
  Edited wirePage({
    required String content,
    required String callback,
    required String pageClass,
    required List<NavParam> params,
  }) {
    final unit = parseString(content: content, throwIfDiagnostics: false).unit;
    final cls = classNamed(unit, pageClass);
    if (cls == null) {
      throw FrxRefusal('no `class $pageClass` in the page file');
    }
    if (declaresField(cls, callback)) {
      return Edited.nothing(content);
    }
    final ctor = _constructor(cls);
    if (ctor == null) {
      throw FrxRefusal('`$pageClass` has no constructor');
    }

    final signature = _signature(params);
    // Before `super.key`, which convention keeps last.
    final superKey = _namedParams(
      ctor,
    ).where((p) => p.name?.lexeme == 'key').firstOrNull;
    return Edited(
      source: applyEdits(content, [
        if (superKey != null)
          Edit.insert(superKey.offset, 'required this.$callback, ')
        else
          _namedParamInsertion(ctor, 'required this.$callback'),
        Edit.insert(cls.end - 1, '\n  final $signature $callback;\n'),
      ]),
      changes: ['$pageClass.$callback ($signature)'],
    );
  }

  /// The callback's type — `void Function(int, String)` for two parameters.
  static String _signature(List<NavParam> params) =>
      'void Function(${params.map((p) => p.type).join(', ')})';

  static ConstructorDeclaration? _constructor(ClassDeclaration c) =>
      c.body.members.whereType<ConstructorDeclaration>().firstOrNull;

  /// The named parameters of [ctor] — the `{…}` group a callback joins.
  static Iterable<FormalParameter> _namedParams(ConstructorDeclaration ctor) =>
      ctor.parameters.parameters.where((p) => p.isNamed);

  /// Splices a named parameter into [ctor], opening a `{…}` group when the
  /// constructor has none.
  ///
  /// `_Vm()` takes nothing at all, and inserting into its parameter list
  /// straight makes the parameter *positional* — `_Vm(required this.onTap)`,
  /// which does not parse. Every generated `_Vm` starts out that way, so this
  /// is the common case rather than the corner one.
  static Edit _namedParamInsertion(
    ConstructorDeclaration ctor,
    String element,
  ) {
    final params = ctor.parameters;
    final named = _namedParams(ctor).toList();
    if (named.isNotEmpty) {
      return insertIntoList(
        elements: named,
        closer: params.rightDelimiter ?? params.rightParenthesis,
        element: element,
      );
    }
    // Dart forbids a constructor from having both an `[optional]` group and a
    // named one, so there is no correct place to put this — appending after
    // the last parameter would splice it inside the brackets and produce
    // source that does not parse. Refused rather than mangled, like a
    // connector frx did not write.
    if (params.parameters.any((p) => p.isOptionalPositional)) {
      throw FrxRefusal(
        'the constructor takes optional positional parameters, which Dart '
        'does not allow alongside named ones — add `$element` by hand',
      );
    }
    final positional = params.parameters;
    return positional.isEmpty
        ? Edit.insert(params.rightParenthesis.offset, '{$element}')
        : Edit.insert(positional.last.end, ', {$element}');
  }

  /// The `_Vm(...)` that `fromStore` returns.
  static Construction? _vmCreation(ClassDeclaration factory) {
    for (final m in factory.body.members.whereType<MethodDeclaration>()) {
      if (m.name.lexeme != 'fromStore') {
        continue;
      }
      final made = Construction.of(resultOf(m.body));
      if (made != null && made.fullName == '_Vm') {
        return made;
      }
    }
    return null;
  }
}
